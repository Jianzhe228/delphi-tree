unit DepTree.Resolver;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DepTree.Model;

type
  TDepTreeResolvedUnit = record
    UnitName: string;
    FileName: string;
    Kind: TDepTreeNodeKind;
  end;

  TDepTreeResolver = class
  private
    FProjectDir: string;
    FSearchPaths: TList<string>;
    FProjectUnits: TDictionary<string, string>;
    FCandidateCache: TDictionary<string, string>;
    function NormalizePath(const APath: string): string;
    function FindCandidateFile(const AUnitName, AOwnerFile: string): string;
  public
    constructor Create(const AProjectDir: string);
    destructor Destroy; override;

    procedure AddSearchPath(const APath: string);
    procedure AddSearchPaths(const APaths: TArray<string>);
    procedure AddProjectUnit(const AUnitName, AFileName: string);

    function Resolve(const ARef: TUsesRef; const AOwnerFile: string): TDepTreeResolvedUnit;
  end;

implementation

uses
  System.Classes;

function UnitShortName(const AUnitName: string): string;
var
  DotPos: Integer;
begin
  Result := AUnitName;
  DotPos := LastDelimiter('.', Result);
  if DotPos > 0 then
    Result := Copy(Result, DotPos + 1, MaxInt);
end;

function IsAbsolutePath(const APath: string): Boolean;
begin
  Result := (APath <> '') and
    ((ExtractFileDrive(APath) <> '') or (Copy(APath, 1, 2) = '\\'));
end;

{ TDepTreeResolver }

constructor TDepTreeResolver.Create(const AProjectDir: string);
begin
  inherited Create;
  FProjectDir := ExcludeTrailingPathDelimiter(ExpandFileName(AProjectDir));
  FSearchPaths := TList<string>.Create;
  FProjectUnits := TDictionary<string, string>.Create;
  FCandidateCache := TDictionary<string, string>.Create;
  AddSearchPath(FProjectDir);
end;

destructor TDepTreeResolver.Destroy;
begin
  FCandidateCache.Free;
  FProjectUnits.Free;
  FSearchPaths.Free;
  inherited;
end;

function TDepTreeResolver.NormalizePath(const APath: string): string;
var
  Path: string;
begin
  Path := Trim(APath);
  if Path = '' then
    Exit('');

  Path := StringReplace(Path, '$(PROJECTDIR)', FProjectDir, [rfReplaceAll, rfIgnoreCase]);
  Path := StringReplace(Path, '$(PROJECTPATH)', FProjectDir, [rfReplaceAll, rfIgnoreCase]);
  Path := StringReplace(Path, '$(PROJECTSOURCEPATH)', FProjectDir, [rfReplaceAll, rfIgnoreCase]);

  if not IsAbsolutePath(Path) then
    Path := IncludeTrailingPathDelimiter(FProjectDir) + Path;

  Result := ExcludeTrailingPathDelimiter(ExpandFileName(Path));
end;

procedure TDepTreeResolver.AddSearchPath(const APath: string);
var
  Path: string;
begin
  Path := NormalizePath(APath);
  if Path = '' then
    Exit;

  if FSearchPaths.IndexOf(Path) < 0 then
    FSearchPaths.Add(Path);
end;

procedure TDepTreeResolver.AddSearchPaths(const APaths: TArray<string>);
var
  Path: string;
begin
  for Path in APaths do
    AddSearchPath(Path);
end;

procedure TDepTreeResolver.AddProjectUnit(const AUnitName, AFileName: string);
var
  Key: string;
begin
  if (AUnitName = '') or (AFileName = '') then
    Exit;

  Key := AnsiLowerCase(AUnitName);
  FProjectUnits.AddOrSetValue(Key, ExpandFileName(AFileName));
  FProjectUnits.AddOrSetValue(AnsiLowerCase(UnitShortName(AUnitName)), ExpandFileName(AFileName));
end;

function TDepTreeResolver.FindCandidateFile(const AUnitName, AOwnerFile: string): string;
var
  Key: string;
  CacheKey: string;
  SearchDir: string;
  Candidate: string;
  CandidateNames: TArray<string>;
  CandidateName: string;
begin
  Result := '';
  Key := AnsiLowerCase(AUnitName);
  if FProjectUnits.TryGetValue(Key, Result) and FileExists(Result) then
    Exit;

  Key := AnsiLowerCase(UnitShortName(AUnitName));
  if FProjectUnits.TryGetValue(Key, Result) and FileExists(Result) then
    Exit;

  // Not (yet) a known project unit - this is the expensive part (a filesystem
  // scan across the owner's directory and every search path), so memoize it
  // per (unit name, owner directory). Keyed by directory rather than globally
  // so the "check the referencing file's own folder first" rule below still
  // gives an independent, correct answer for each folder.
  CacheKey := AnsiLowerCase(AUnitName) + '|' + AnsiLowerCase(ExtractFileDir(AOwnerFile));
  if FCandidateCache.TryGetValue(CacheKey, Result) then
    Exit;

  CandidateNames := TArray<string>.Create(AUnitName + '.pas', UnitShortName(AUnitName) + '.pas');

  if AOwnerFile <> '' then
  begin
    SearchDir := ExtractFileDir(AOwnerFile);
    for CandidateName in CandidateNames do
    begin
      Candidate := IncludeTrailingPathDelimiter(SearchDir) + CandidateName;
      if FileExists(Candidate) then
      begin
        Result := ExpandFileName(Candidate);
        FCandidateCache.Add(CacheKey, Result);
        Exit;
      end;
    end;
  end;

  for SearchDir in FSearchPaths do
  begin
    for CandidateName in CandidateNames do
    begin
      Candidate := IncludeTrailingPathDelimiter(SearchDir) + CandidateName;
      if FileExists(Candidate) then
      begin
        Result := ExpandFileName(Candidate);
        FCandidateCache.Add(CacheKey, Result);
        Exit;
      end;
    end;
  end;

  FCandidateCache.Add(CacheKey, '');
end;

function TDepTreeResolver.Resolve(const ARef: TUsesRef;
  const AOwnerFile: string): TDepTreeResolvedUnit;
var
  ExplicitFile: string;
begin
  Result.UnitName := ARef.UnitName;
  Result.FileName := '';
  Result.Kind := dnExternal;

  if ARef.ExplicitPath <> '' then
  begin
    ExplicitFile := ARef.ExplicitPath;
    if not IsAbsolutePath(ExplicitFile) then
    begin
      if AOwnerFile <> '' then
        ExplicitFile := IncludeTrailingPathDelimiter(ExtractFileDir(AOwnerFile)) + ExplicitFile
      else
        ExplicitFile := IncludeTrailingPathDelimiter(FProjectDir) + ExplicitFile;
    end;

    ExplicitFile := ExpandFileName(ExplicitFile);
    Result.FileName := ExplicitFile;
    if FileExists(ExplicitFile) then
      Result.Kind := dnUnit
    else
      Result.Kind := dnMissing;
    Exit;
  end;

  Result.FileName := FindCandidateFile(ARef.UnitName, AOwnerFile);
  if Result.FileName <> '' then
    Result.Kind := dnUnit
  else
    Result.Kind := dnExternal;
end;

end.
