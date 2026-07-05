unit DepTree.OTAUtils;

interface

uses
  System.SysUtils,
  DepTree.Model;

function ReadActiveProjectInfo(out AProject: TDepTreeProjectInfo): Boolean;
function ReadSourceText(const AFileName: string): string;
function OpenFileInIDE(const AFileName: string; ALine: Integer = 0): Boolean;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Variants,
  ToolsAPI;

function SplitSearchPaths(const ASearchPaths: string): TArray<string>;
var
  Items: TStringList;
  Index: Integer;
begin
  Items := TStringList.Create;
  try
    Items.StrictDelimiter := True;
    Items.Delimiter := ';';
    Items.DelimitedText := ASearchPaths;
    SetLength(Result, Items.Count);
    for Index := 0 to Items.Count - 1 do
      Result[Index] := Items[Index];
  finally
    Items.Free;
  end;
end;

function AbsoluteFromProjectDir(const AProjectDir, AFileName: string): string;
begin
  Result := Trim(AFileName);
  if Result = '' then
    Exit('');

  if ExtractFileDrive(Result) = '' then
    Result := IncludeTrailingPathDelimiter(AProjectDir) + Result;

  Result := ExpandFileName(Result);
end;

procedure AddSourceFile(var AFiles: TArray<string>; const AProjectDir, AFileName: string);
var
  FileName: string;
  Index: Integer;
begin
  FileName := AbsoluteFromProjectDir(AProjectDir, AFileName);
  if FileName = '' then
    Exit;

  for Index := 0 to High(AFiles) do
  begin
    if SameText(AFiles[Index], FileName) then
      Exit;
  end;

  SetLength(AFiles, Length(AFiles) + 1);
  AFiles[High(AFiles)] := FileName;
end;

function TryReadProjectSearchPath(const AProject: IOTAProject): string;
var
  Options: IOTAProjectOptions;
begin
  Result := '';
  if AProject = nil then
    Exit;

  try
    Options := AProject.ProjectOptions;
    if Options <> nil then
      Result := VarToStr(Options.Values['DCC_UnitSearchPath']);
  except
    Result := '';
  end;
end;

function ReadActiveProjectInfo(out AProject: TDepTreeProjectInfo): Boolean;
var
  ModuleServices: IOTAModuleServices;
  Project: IOTAProject;
  ModuleInfo: IOTAModuleInfo;
  Index: Integer;
  FileName: string;
  SearchPathText: string;
begin
  AProject := Default(TDepTreeProjectInfo);
  Result := False;

  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;

  Project := ModuleServices.GetActiveProject;
  if Project = nil then
    Exit;

  AProject.ProjectFile := ExpandFileName(Project.FileName);
  AProject.ProjectName := ChangeFileExt(ExtractFileName(AProject.ProjectFile), '');
  AProject.ProjectDir := ExtractFileDir(AProject.ProjectFile);

  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    ModuleInfo := Project.GetModule(Index);
    if ModuleInfo = nil then
      Continue;

    FileName := AbsoluteFromProjectDir(AProject.ProjectDir, ModuleInfo.FileName);
    AddSourceFile(AProject.SourceFiles, AProject.ProjectDir, FileName);
    if SameText(ExtractFileExt(FileName), '.dpr') or SameText(ExtractFileExt(FileName), '.dpk') then
      AProject.MainSource := FileName;
  end;

  if AProject.MainSource = '' then
  begin
    FileName := ChangeFileExt(AProject.ProjectFile, '.dpr');
    if FileExists(FileName) then
    begin
      AProject.MainSource := FileName;
      AddSourceFile(AProject.SourceFiles, AProject.ProjectDir, FileName);
    end;
  end;

  SearchPathText := TryReadProjectSearchPath(Project);
  AProject.UnitSearchPaths := SplitSearchPaths(SearchPathText);
  Result := True;
end;

function TryReadOpenSourceText(const AFileName: string; out ASource: string): Boolean;
const
  ChunkSize = 8192;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  SourceEditor: IOTASourceEditor;
  Reader: IOTAEditReader;
  Index: Integer;
  Position: Integer;
  ReadCount: Integer;
  Buffer: array[0..ChunkSize - 1] of AnsiChar;
  Chunk: AnsiString;
begin
  Result := False;
  ASource := '';

  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;

  Module := ModuleServices.FindModule(AFileName);
  if Module = nil then
    Exit;

  for Index := 0 to Module.GetModuleFileCount - 1 do
  begin
    if Supports(Module.GetModuleFileEditor(Index), IOTASourceEditor, SourceEditor) then
    begin
      Reader := SourceEditor.CreateReader;
      Position := 0;
      repeat
        FillChar(Buffer, SizeOf(Buffer), 0);
        ReadCount := Reader.GetText(Position, PAnsiChar(@Buffer[0]), SizeOf(Buffer));
        if ReadCount > 0 then
        begin
          SetString(Chunk, PAnsiChar(@Buffer[0]), ReadCount);
          ASource := ASource + string(Chunk);
          Inc(Position, ReadCount);
        end;
      until ReadCount < SizeOf(Buffer);

      Exit(True);
    end;
  end;
end;

function ReadSourceText(const AFileName: string): string;
begin
  if TryReadOpenSourceText(AFileName, Result) then
    Exit;

  if FileExists(AFileName) then
    Result := TFile.ReadAllText(AFileName, TEncoding.Default)
  else
    Result := '';
end;

function OpenFileInIDE(const AFileName: string; ALine: Integer): Boolean;
var
  ActionServices: IOTAActionServices;
  ModuleServices: IOTAModuleServices;
  Ext: string;

  function ShowSourceOf(AModule: IOTAModule): Boolean;
  var
    Index: Integer;
    Editor: IOTASourceEditor;
  begin
    Result := False;
    if AModule = nil then
      Exit;

    for Index := 0 to AModule.GetModuleFileCount - 1 do
    begin
      if Supports(AModule.GetModuleFileEditor(Index), IOTASourceEditor, Editor) then
      begin
        Editor.Show;
        Exit(True);
      end;
    end;
  end;

begin
  Result := False;
  if AFileName = '' then
    Exit;

  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;

  // The IDE's OpenFile can report success for a project's own main source
  // (.dpr/.dpk) without ever showing an editor, since it's already loaded as
  // the active project - go straight to the project instead of trusting it.
  Ext := AnsiLowerCase(ExtractFileExt(AFileName));
  if (Ext = '.dpr') or (Ext = '.dpk') then
  begin
    Result := ShowSourceOf(ModuleServices.GetActiveProject);
    if Result then
      Exit;
  end
  else if Supports(BorlandIDEServices, IOTAActionServices, ActionServices) then
  begin
    Result := ActionServices.OpenFile(AFileName);
    if Result then
      Exit;
  end;

  Result := ShowSourceOf(ModuleServices.OpenModule(AFileName));
end;

end.
