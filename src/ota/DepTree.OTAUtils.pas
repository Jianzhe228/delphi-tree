unit DepTree.OTAUtils;

interface

uses
  System.SysUtils,
  DepTree.Model;

type
  TDepTreeNewFileKind = (nfVclForm, nfVclFrame, nfDataModule, nfUnit);

function ReadActiveProjectInfo(out AProject: TDepTreeProjectInfo): Boolean;
function ReadSourceText(const AFileName: string): string;
function OpenFileInIDE(const AFileName: string; ALine: Integer = 0): Boolean;
function CreateNewProjectFile(AKind: TDepTreeNewFileKind; const ATargetDir, AUnitName,
  AFormName: string; out AFileName: string): Boolean;
function DeleteProjectFile(const AFileName: string): Boolean;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Variants,
  Winapi.ShellAPI,
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

function BuildUnitSource(const AUnitName: string): string;
begin
  Result := 'unit ' + AUnitName + ';' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    'end.' + sLineBreak;
end;

function BuildFormSource(const AUnitName, AFormName: string): string;
begin
  Result := 'unit ' + AUnitName + ';' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'uses' + sLineBreak +
    '  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,' + sLineBreak +
    '  Vcl.Controls, Vcl.Forms, Vcl.Dialogs;' + sLineBreak + sLineBreak +
    'type' + sLineBreak +
    '  T' + AFormName + ' = class(TForm)' + sLineBreak +
    '  private' + sLineBreak +
    '    { Private declarations }' + sLineBreak +
    '  public' + sLineBreak +
    '    { Public declarations }' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    'var' + sLineBreak +
    '  ' + AFormName + ': T' + AFormName + ';' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    '{$R *.dfm}' + sLineBreak + sLineBreak +
    'end.' + sLineBreak;
end;

function BuildFrameSource(const AUnitName, AFrameName: string): string;
begin
  Result := 'unit ' + AUnitName + ';' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'uses' + sLineBreak +
    '  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,' + sLineBreak +
    '  Vcl.Controls, Vcl.Forms, Vcl.Dialogs;' + sLineBreak + sLineBreak +
    'type' + sLineBreak +
    '  T' + AFrameName + ' = class(TFrame)' + sLineBreak +
    '  private' + sLineBreak +
    '    { Private declarations }' + sLineBreak +
    '  public' + sLineBreak +
    '    { Public declarations }' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    '{$R *.dfm}' + sLineBreak + sLineBreak +
    'end.' + sLineBreak;
end;

function BuildDataModuleSource(const AUnitName, AModuleName: string): string;
begin
  Result := 'unit ' + AUnitName + ';' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'uses' + sLineBreak +
    '  System.SysUtils, System.Classes;' + sLineBreak + sLineBreak +
    'type' + sLineBreak +
    '  T' + AModuleName + ' = class(TDataModule)' + sLineBreak +
    '  private' + sLineBreak +
    '    { Private declarations }' + sLineBreak +
    '  public' + sLineBreak +
    '    { Public declarations }' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    'var' + sLineBreak +
    '  ' + AModuleName + ': T' + AModuleName + ';' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    '{%CLASSGROUP ''Vcl.Controls.TControl''}' + sLineBreak + sLineBreak +
    '{$R *.dfm}' + sLineBreak + sLineBreak +
    'end.' + sLineBreak;
end;

function BuildFormDfm(const AFormName: string): string;
begin
  Result := 'object ' + AFormName + ': T' + AFormName + sLineBreak +
    '  Left = 0' + sLineBreak +
    '  Top = 0' + sLineBreak +
    '  Caption = ' + QuotedStr(AFormName) + sLineBreak +
    '  ClientHeight = 441' + sLineBreak +
    '  ClientWidth = 624' + sLineBreak +
    '  Color = clBtnFace' + sLineBreak +
    '  Font.Charset = DEFAULT_CHARSET' + sLineBreak +
    '  Font.Color = clWindowText' + sLineBreak +
    '  Font.Height = -12' + sLineBreak +
    '  Font.Name = ''Segoe UI''' + sLineBreak +
    '  Font.Style = []' + sLineBreak +
    '  TextHeight = 15' + sLineBreak +
    'end' + sLineBreak;
end;

function BuildFrameDfm(const AFrameName: string): string;
begin
  Result := 'object ' + AFrameName + ': T' + AFrameName + sLineBreak +
    '  Left = 0' + sLineBreak +
    '  Top = 0' + sLineBreak +
    '  Width = 320' + sLineBreak +
    '  Height = 240' + sLineBreak +
    '  TabOrder = 0' + sLineBreak +
    'end' + sLineBreak;
end;

function BuildDataModuleDfm(const AModuleName: string): string;
begin
  Result := 'object ' + AModuleName + ': T' + AModuleName + sLineBreak +
    '  Height = 480' + sLineBreak +
    '  Width = 640' + sLineBreak +
    'end' + sLineBreak;
end;

function CreateNewProjectFile(AKind: TDepTreeNewFileKind; const ATargetDir, AUnitName,
  AFormName: string; out AFileName: string): Boolean;
var
  ModuleServices: IOTAModuleServices;
  Project: IOTAProject;
  DfmFileName: string;
  Source: string;
  DfmSource: string;
begin
  Result := False;
  AFileName := '';
  if (Trim(ATargetDir) = '') or (Trim(AUnitName) = '') then
    Exit;
  if (AKind <> nfUnit) and (Trim(AFormName) = '') then
    Exit;

  AFileName := IncludeTrailingPathDelimiter(ATargetDir) + AUnitName + '.pas';
  DfmFileName := ChangeFileExt(AFileName, '.dfm');
  if FileExists(AFileName) or ((AKind <> nfUnit) and FileExists(DfmFileName)) then
  begin
    AFileName := '';
    Exit;
  end;

  case AKind of
    nfVclForm:
      begin
        Source := BuildFormSource(AUnitName, AFormName);
        DfmSource := BuildFormDfm(AFormName);
      end;
    nfVclFrame:
      begin
        Source := BuildFrameSource(AUnitName, AFormName);
        DfmSource := BuildFrameDfm(AFormName);
      end;
    nfDataModule:
      begin
        Source := BuildDataModuleSource(AUnitName, AFormName);
        DfmSource := BuildDataModuleDfm(AFormName);
      end;
  else
    Source := BuildUnitSource(AUnitName);
    DfmSource := '';
  end;

  TFile.WriteAllText(AFileName, Source, TEncoding.UTF8);
  if DfmSource <> '' then
    TFile.WriteAllText(DfmFileName, DfmSource, TEncoding.UTF8);

  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
  begin
    Project := ModuleServices.GetActiveProject;
    if Project <> nil then
      try
        Project.AddFile(AFileName, True);
      except
        // Not fatal - the files exist on disk and can be added to the
        // project manually if this fails.
      end;
  end;

  Result := True;
end;

function DeleteProjectFile(const AFileName: string): Boolean;
var
  ModuleServices: IOTAModuleServices;
  Project: IOTAProject;
  FileOp: TSHFileOpStruct;
  NameBuffer: array[0..2047] of Char;
  DfmFileName: string;
  Paths: string;
begin
  Result := False;
  if (AFileName = '') or not FileExists(AFileName) then
    Exit;

  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
  begin
    Project := ModuleServices.GetActiveProject;
    if Project <> nil then
      try
        Project.RemoveFile(AFileName);
      except
        // Not fatal - still attempt to delete the physical file below, even
        // if the file was not (or no longer) tracked by the project.
      end;
  end;

  // pFrom is a double-null-terminated list; include the paired .dfm (if any)
  // so deleting a form/frame/data module does not leave an orphaned form file.
  Paths := AFileName;
  DfmFileName := ChangeFileExt(AFileName, '.dfm');
  if FileExists(DfmFileName) then
    Paths := Paths + #0 + DfmFileName;
  if Length(Paths) > High(NameBuffer) - 1 then
    Exit;

  FillChar(NameBuffer, SizeOf(NameBuffer), 0);
  Move(PChar(Paths)^, NameBuffer, Length(Paths) * SizeOf(Char));

  FillChar(FileOp, SizeOf(FileOp), 0);
  FileOp.wFunc := FO_DELETE;
  FileOp.pFrom := NameBuffer;
  FileOp.fFlags := FOF_ALLOWUNDO or FOF_NOCONFIRMATION or FOF_SILENT or FOF_NOERRORUI;
  Result := SHFileOperation(FileOp) = 0;
end;

end.
