unit DepTree.ProjectAnalyzer;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DepTree.Model;

type
  TDepTreeReadFileFunc = reference to function(const AFileName: string): string;
  TDepTreeCancelledFunc = reference to function: Boolean;
  TDepTreeProgressProc = reference to procedure(AFilesParsed: Integer);

  // Parse results (unit name + uses refs) keyed by file, validated against the
  // file's size and last-write time, so unchanged files are not re-read and
  // re-lexed on every refresh.
  TDepTreeParseCache = class
  private
    type
      TEntry = record
        UnitName: string;
        UsesRefs: TUsesRefArray;
        Size: Int64;
        TimeStamp: TDateTime;
      end;
    var
      FEntries: TDictionary<string, TEntry>;
  public
    constructor Create;
    destructor Destroy; override;

    function TryGet(const AFileName: string; out AUnitName: string;
      out AUsesRefs: TUsesRefArray): Boolean;
    procedure Store(const AFileName, AUnitName: string;
      const AUsesRefs: TUsesRefArray; ASize: Int64; ATimeStamp: TDateTime);
  end;

  TDepTreeProjectAnalyzer = class
  public
    // AOverrideTexts (keyed by DepTreeNormalizeFileKey) supplies in-editor text
    // for open files; those entries bypass ACache because the editor buffer can
    // differ from what is on disk.
    class function BuildGraph(const AProject: TDepTreeProjectInfo;
      const AReadFile: TDepTreeReadFileFunc;
      AOverrideTexts: TDictionary<string, string> = nil;
      ACache: TDepTreeParseCache = nil;
      const ACancelled: TDepTreeCancelledFunc = nil;
      const AProgress: TDepTreeProgressProc = nil): TDepTreeGraph; static;
  end;

  // Runs BuildGraph off the IDE main thread. The owner must gather all
  // ToolsAPI state up front (project info, open editor texts) - nothing in
  // Execute may touch the IDE. Completion/progress is polled by the UI owner.
  TDepTreeGraphBuildThread = class(TThread)
  private
    FProject: TDepTreeProjectInfo;
    FOverrideTexts: TDictionary<string, string>;
    FCache: TDepTreeParseCache;
    FGraph: TDepTreeGraph;
    FError: string;
    FCancelled: Boolean;
    FParsedCount: Integer;
  protected
    procedure Execute; override;
  public
    // AOverrideTexts is owned by the thread; ACache is borrowed and must
    // outlive it. The thread is created suspended; call Start after storing it.
    constructor Create(const AProject: TDepTreeProjectInfo;
      AOverrideTexts: TDictionary<string, string>; ACache: TDepTreeParseCache);
    destructor Destroy; override;

    procedure Cancel;
    function DetachGraph: TDepTreeGraph;

    property ProjectInfo: TDepTreeProjectInfo read FProject;
    property Error: string read FError;
    property Cancelled: Boolean read FCancelled;
    property ParsedCount: Integer read FParsedCount;
  end;

implementation

uses
  System.IOUtils,
  DepTree.UsesLexer,
  DepTree.Resolver;

function IsPascalSource(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := AnsiLowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk');
end;

function TryGetFileStamp(const AFileName: string; out ASize: Int64;
  out ATimeStamp: TDateTime): Boolean;
var
  SearchRec: TSearchRec;
begin
  ASize := 0;
  ATimeStamp := 0;
  Result := (AFileName <> '') and (FindFirst(AFileName, faAnyFile, SearchRec) = 0);
  if not Result then
    Exit;

  try
    ASize := SearchRec.Size;
    ATimeStamp := SearchRec.TimeStamp;
  finally
    FindClose(SearchRec);
  end;
end;

function AddUniqueFile(AFiles: TList<string>; ASeen: TDictionary<string, Boolean>;
  const AFileName: string): Boolean;
var
  FileName: string;
  Key: string;
begin
  Result := False;
  FileName := Trim(AFileName);
  if (FileName = '') or not IsPascalSource(FileName) then
    Exit;

  FileName := ExpandFileName(FileName);
  Key := AnsiLowerCase(FileName);
  if ASeen.ContainsKey(Key) then
    Exit;

  ASeen.Add(Key, True);
  AFiles.Add(FileName);
  Result := True;
end;

{ TDepTreeParseCache }

constructor TDepTreeParseCache.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TEntry>.Create;
end;

destructor TDepTreeParseCache.Destroy;
begin
  FEntries.Free;
  inherited;
end;

function TDepTreeParseCache.TryGet(const AFileName: string; out AUnitName: string;
  out AUsesRefs: TUsesRefArray): Boolean;
var
  Entry: TEntry;
  Size: Int64;
  TimeStamp: TDateTime;
begin
  AUnitName := '';
  AUsesRefs := nil;

  Result := FEntries.TryGetValue(DepTreeNormalizeFileKey(AFileName), Entry) and
    TryGetFileStamp(AFileName, Size, TimeStamp) and
    (Entry.Size = Size) and (Entry.TimeStamp = TimeStamp);
  if not Result then
    Exit;

  AUnitName := Entry.UnitName;
  AUsesRefs := Entry.UsesRefs;
end;

procedure TDepTreeParseCache.Store(const AFileName, AUnitName: string;
  const AUsesRefs: TUsesRefArray; ASize: Int64; ATimeStamp: TDateTime);
var
  Entry: TEntry;
begin
  Entry.UnitName := AUnitName;
  Entry.UsesRefs := AUsesRefs;
  Entry.Size := ASize;
  Entry.TimeStamp := ATimeStamp;
  FEntries.AddOrSetValue(DepTreeNormalizeFileKey(AFileName), Entry);
end;

{ TDepTreeProjectAnalyzer }

class function TDepTreeProjectAnalyzer.BuildGraph(const AProject: TDepTreeProjectInfo;
  const AReadFile: TDepTreeReadFileFunc;
  AOverrideTexts: TDictionary<string, string>;
  ACache: TDepTreeParseCache;
  const ACancelled: TDepTreeCancelledFunc;
  const AProgress: TDepTreeProgressProc): TDepTreeGraph;
var
  Files: TList<string>;
  FilesSeen: TDictionary<string, Boolean>;
  RefsByFile: TDictionary<string, TUsesRefArray>;
  UnitByFile: TDictionary<string, string>;
  Resolver: TDepTreeResolver;
  FileName: string;
  UnitName: string;
  RootFile: string;
  RootNode: TDepTreeNode;
  OwnerNode: TDepTreeNode;
  TargetNode: TDepTreeNode;
  UsesRefs: TUsesRefArray;
  UsesRef: TUsesRef;
  Resolved: TDepTreeResolvedUnit;
  FileIndex: Integer;
  ParsedCount: Integer;

  function IsCancelled: Boolean;
  begin
    Result := Assigned(ACancelled) and ACancelled();
  end;

  procedure EnsureParsed(const AFileName: string);
  var
    Key: string;
    Source: string;
    ParsedUnitName: string;
    ParsedRefs: TUsesRefArray;
    Size: Int64;
    TimeStamp: TDateTime;
    Stamped: Boolean;
  begin
    if AFileName = '' then
      Exit;

    Key := DepTreeNormalizeFileKey(AFileName);
    if RefsByFile.ContainsKey(Key) then
      Exit;

    if (AOverrideTexts <> nil) and AOverrideTexts.TryGetValue(Key, Source) then
    begin
      ParsedUnitName := ExtractModuleName(Source, AFileName);
      ParsedRefs := ExtractUses(Source);
    end
    else if (ACache = nil) or not ACache.TryGet(AFileName, ParsedUnitName, ParsedRefs) then
    begin
      // Stamp before reading so a write that lands mid-read leaves a stale
      // stamp behind and the entry self-invalidates on the next refresh.
      Stamped := TryGetFileStamp(AFileName, Size, TimeStamp);
      Source := AReadFile(AFileName);
      ParsedUnitName := ExtractModuleName(Source, AFileName);
      ParsedRefs := ExtractUses(Source);
      if (ACache <> nil) and Stamped then
        ACache.Store(AFileName, ParsedUnitName, ParsedRefs, Size, TimeStamp);
    end;

    UnitByFile.AddOrSetValue(Key, ParsedUnitName);
    RefsByFile.AddOrSetValue(Key, ParsedRefs);
    Resolver.AddProjectUnit(ParsedUnitName, AFileName);

    Inc(ParsedCount);
    if Assigned(AProgress) then
      AProgress(ParsedCount);
  end;

begin
  Files := nil;
  FilesSeen := nil;
  RefsByFile := nil;
  UnitByFile := nil;
  Resolver := nil;
  ParsedCount := 0;

  Result := TDepTreeGraph.Create;
  try
    try
      Files := TList<string>.Create;
      FilesSeen := TDictionary<string, Boolean>.Create;
      RefsByFile := TDictionary<string, TUsesRefArray>.Create;
      UnitByFile := TDictionary<string, string>.Create;
      Resolver := TDepTreeResolver.Create(AProject.ProjectDir);

      Resolver.AddSearchPaths(AProject.UnitSearchPaths);

      AddUniqueFile(Files, FilesSeen, AProject.MainSource);
      for FileName in AProject.SourceFiles do
        AddUniqueFile(Files, FilesSeen, FileName);

      RootFile := AProject.MainSource;
      if (RootFile = '') and (Files.Count > 0) then
        RootFile := Files[0];

      // Parse the explicit project files first so the resolver prefers them
      // over same-named files sitting on the search path.
      for FileName in Files do
      begin
        if IsCancelled then
          Exit;
        EnsureParsed(FileName);
      end;

      FileIndex := 0;
      while FileIndex < Files.Count do
      begin
        if IsCancelled then
          Exit;

        FileName := Files[FileIndex];
        EnsureParsed(FileName);

        UnitByFile.TryGetValue(DepTreeNormalizeFileKey(FileName), UnitName);
        if SameText(FileName, RootFile) then
          OwnerNode := Result.EnsureNode(UnitName, FileName, dnProject)
        else
          OwnerNode := Result.EnsureNode(UnitName, FileName, dnUnit);

        if not RefsByFile.TryGetValue(DepTreeNormalizeFileKey(FileName), UsesRefs) then
          UsesRefs := nil;

        for UsesRef in UsesRefs do
        begin
          Resolved := Resolver.Resolve(UsesRef, FileName);
          TargetNode := Result.EnsureNode(Resolved.UnitName, Resolved.FileName, Resolved.Kind);
          Result.AddEdge(OwnerNode.Id, TargetNode.Id, UsesRef.Section, UsesRef.Line);

          if (Resolved.Kind = dnUnit) and (Resolved.FileName <> '') and
            FileExists(Resolved.FileName) and IsPascalSource(Resolved.FileName) then
          begin
            AddUniqueFile(Files, FilesSeen, Resolved.FileName);
            EnsureParsed(Resolved.FileName);
          end;
        end;

        Inc(FileIndex);
      end;

      if RootFile <> '' then
      begin
        UnitByFile.TryGetValue(DepTreeNormalizeFileKey(RootFile), UnitName);
        RootNode := Result.EnsureNode(UnitName, RootFile, dnProject);
        if AProject.ProjectName <> '' then
          RootNode.DisplayName := AProject.ProjectName;
      end
      else if AProject.ProjectName <> '' then
        Result.EnsureNode(AProject.ProjectName, AProject.ProjectFile, dnProject);
    finally
      Resolver.Free;
      UnitByFile.Free;
      RefsByFile.Free;
      FilesSeen.Free;
      Files.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TDepTreeGraphBuildThread }

constructor TDepTreeGraphBuildThread.Create(const AProject: TDepTreeProjectInfo;
  AOverrideTexts: TDictionary<string, string>; ACache: TDepTreeParseCache);
begin
  inherited Create(True);
  FProject := AProject;
  FOverrideTexts := AOverrideTexts;
  FCache := ACache;
end;

destructor TDepTreeGraphBuildThread.Destroy;
begin
  FGraph.Free;
  FOverrideTexts.Free;
  inherited;
end;

procedure TDepTreeGraphBuildThread.Cancel;
begin
  FCancelled := True;
  Terminate;
end;

function TDepTreeGraphBuildThread.DetachGraph: TDepTreeGraph;
begin
  Result := FGraph;
  FGraph := nil;
end;

procedure TDepTreeGraphBuildThread.Execute;
begin
  try
    FGraph := TDepTreeProjectAnalyzer.BuildGraph(FProject,
      function(const AFileName: string): string
      begin
        if FileExists(AFileName) then
          Result := TFile.ReadAllText(AFileName, TEncoding.Default)
        else
          Result := '';
      end,
      FOverrideTexts,
      FCache,
      function: Boolean
      begin
        Result := FCancelled or Terminated;
      end,
      procedure(AFilesParsed: Integer)
      begin
        FParsedCount := AFilesParsed;
      end);
  except
    on E: Exception do
      FError := E.Message;
  end;
end;

end.
