unit DepTree.ProjectAnalyzer;

interface

uses
  System.SysUtils,
  DepTree.Model;

type
  TDepTreeReadFileFunc = reference to function(const AFileName: string): string;

  TDepTreeProjectAnalyzer = class
  public
    class function BuildGraph(const AProject: TDepTreeProjectInfo;
      const AReadFile: TDepTreeReadFileFunc): TDepTreeGraph; static;
  end;

implementation

uses
  System.Generics.Collections,
  DepTree.UsesLexer,
  DepTree.Resolver;

function NormalizeFileKey(const AFileName: string): string;
begin
  Result := AnsiLowerCase(ExpandFileName(AFileName));
end;

function IsPascalSource(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := AnsiLowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk');
end;

function AddUniqueFile(AFiles: TList<string>; const AFileName: string): Boolean;
var
  FileName: string;
  Existing: string;
begin
  Result := False;
  FileName := Trim(AFileName);
  if (FileName = '') or not IsPascalSource(FileName) then
    Exit;

  FileName := ExpandFileName(FileName);
  for Existing in AFiles do
  begin
    if SameText(Existing, FileName) then
      Exit;
  end;

  AFiles.Add(FileName);
  Result := True;
end;

class function TDepTreeProjectAnalyzer.BuildGraph(const AProject: TDepTreeProjectInfo;
  const AReadFile: TDepTreeReadFileFunc): TDepTreeGraph;
var
  Files: TList<string>;
  SourceByFile: TDictionary<string, string>;
  UnitByFile: TDictionary<string, string>;
  Resolver: TDepTreeResolver;
  FileName: string;
  Source: string;
  UnitName: string;
  RootFile: string;
  RootNode: TDepTreeNode;
  OwnerNode: TDepTreeNode;
  TargetNode: TDepTreeNode;
  UsesRefs: TUsesRefArray;
  UsesRef: TUsesRef;
  Resolved: TDepTreeResolvedUnit;
  FileIndex: Integer;

  procedure EnsureSourceLoaded(const AFileName: string);
  var
    Key: string;
  begin
    if AFileName = '' then
      Exit;

    Key := NormalizeFileKey(AFileName);
    if SourceByFile.ContainsKey(Key) then
      Exit;

    Source := AReadFile(AFileName);
    SourceByFile.AddOrSetValue(Key, Source);
    UnitName := ExtractModuleName(Source, AFileName);
    UnitByFile.AddOrSetValue(Key, UnitName);
    Resolver.AddProjectUnit(UnitName, AFileName);
  end;
begin
  Result := TDepTreeGraph.Create;
  Files := TList<string>.Create;
  SourceByFile := TDictionary<string, string>.Create;
  UnitByFile := TDictionary<string, string>.Create;
  Resolver := TDepTreeResolver.Create(AProject.ProjectDir);
  try
    Resolver.AddSearchPaths(AProject.UnitSearchPaths);

    AddUniqueFile(Files, AProject.MainSource);
    for FileName in AProject.SourceFiles do
      AddUniqueFile(Files, FileName);

    RootFile := AProject.MainSource;
    if (RootFile = '') and (Files.Count > 0) then
      RootFile := Files[0];

    for FileName in Files do
      EnsureSourceLoaded(FileName);

    FileIndex := 0;
    while FileIndex < Files.Count do
    begin
      FileName := Files[FileIndex];
      EnsureSourceLoaded(FileName);

      UnitByFile.TryGetValue(NormalizeFileKey(FileName), UnitName);
      if SameText(FileName, RootFile) then
        OwnerNode := Result.EnsureNode(UnitName, FileName, dnProject)
      else
        OwnerNode := Result.EnsureNode(UnitName, FileName, dnUnit);

      if not SourceByFile.TryGetValue(NormalizeFileKey(FileName), Source) then
        Source := '';

      UsesRefs := ExtractUses(Source);
      for UsesRef in UsesRefs do
      begin
        Resolved := Resolver.Resolve(UsesRef, FileName);
        TargetNode := Result.EnsureNode(Resolved.UnitName, Resolved.FileName, Resolved.Kind);
        Result.AddEdge(OwnerNode.Id, TargetNode.Id, UsesRef.Section, UsesRef.Line);

        if (Resolved.Kind = dnUnit) and (Resolved.FileName <> '') and
          FileExists(Resolved.FileName) and IsPascalSource(Resolved.FileName) then
        begin
          AddUniqueFile(Files, Resolved.FileName);
          EnsureSourceLoaded(Resolved.FileName);
        end;
      end;

      Inc(FileIndex);
    end;

    if RootFile <> '' then
    begin
      UnitByFile.TryGetValue(NormalizeFileKey(RootFile), UnitName);
      RootNode := Result.EnsureNode(UnitName, RootFile, dnProject);
      if AProject.ProjectName <> '' then
        RootNode.DisplayName := AProject.ProjectName;
    end
    else if AProject.ProjectName <> '' then
      Result.EnsureNode(AProject.ProjectName, AProject.ProjectFile, dnProject);
  finally
    Resolver.Free;
    UnitByFile.Free;
    SourceByFile.Free;
    Files.Free;
  end;
end;

end.
