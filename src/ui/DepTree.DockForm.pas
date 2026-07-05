unit DepTree.DockForm;

interface

procedure RegisterDepTreeDockForm;
procedure UnregisterDepTreeDockForm;
procedure ShowDepTreeWindow;
procedure RefreshDepTreeWindow;
function IsDepTreeWindowVisible: Boolean;

implementation

uses
  System.SysUtils,
  System.IniFiles,
  Vcl.ActnList,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.Dialogs,
  Vcl.ImgList,
  Vcl.Menus,
  DesignIntf,
  ToolsAPI,
  DepTree.Frame;

type
  TDepTreeDockableForm = class(TInterfacedObject, INTACustomDockableForm)
  public
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolBarActionList: TCustomActionList;
    function GetToolBarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string;
      IsProject: Boolean);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
    procedure HostDestroyed(Sender: TObject);
  end;

var
  GDockForm: INTACustomDockableForm;
  GDockFormObj: TDepTreeDockableForm;
  GDockHost: TForm;
  GFrame: TDepTreeFrame;
  GRegistered: Boolean;

function TDepTreeDockableForm.GetCaption: string;
begin
  Result := 'Dependency Tree';
end;

function TDepTreeDockableForm.GetIdentifier: string;
begin
  Result := 'Codex.DelphiDependencyTree';
end;

function TDepTreeDockableForm.GetFrameClass: TCustomFrameClass;
begin
  Result := TDepTreeFrame;
end;

procedure TDepTreeDockableForm.FrameCreated(AFrame: TCustomFrame);
begin
  if AFrame is TDepTreeFrame then
    GFrame := TDepTreeFrame(AFrame);
end;

function TDepTreeDockableForm.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TDepTreeDockableForm.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TDepTreeDockableForm.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

function TDepTreeDockableForm.GetToolBarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TDepTreeDockableForm.GetToolBarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TDepTreeDockableForm.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TDepTreeDockableForm.LoadWindowState(Desktop: TCustomIniFile;
  const Section: string);
begin
end;

procedure TDepTreeDockableForm.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
begin
end;

function TDepTreeDockableForm.GetEditState: TEditState;
begin
  Result := [];
end;

function TDepTreeDockableForm.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure TDepTreeDockableForm.HostDestroyed(Sender: TObject);
begin
  GDockHost := nil;
  GFrame := nil;
end;

procedure EnsureDockFormObject;
begin
  if GDockForm = nil then
  begin
    GDockFormObj := TDepTreeDockableForm.Create;
    GDockForm := GDockFormObj;
  end;
end;

procedure RegisterDepTreeDockForm;
var
  NTAServices: INTAServices;
begin
  if GRegistered then
    Exit;

  if not Supports(BorlandIDEServices, INTAServices, NTAServices) then
    Exit;

  EnsureDockFormObject;
  NTAServices.RegisterDockableForm(GDockForm);
  GRegistered := True;
end;

procedure UnregisterDepTreeDockForm;
var
  NTAServices: INTAServices;
begin
  if not GRegistered then
    Exit;

  if Supports(BorlandIDEServices, INTAServices, NTAServices) then
    NTAServices.UnregisterDockableForm(GDockForm);
  GRegistered := False;
end;

procedure EnsureDockForm;
var
  NTAServices: INTAServices;
begin
  if GDockHost <> nil then
    Exit;

  if not Supports(BorlandIDEServices, INTAServices, NTAServices) then
    Exit;

  EnsureDockFormObject;
  GDockHost := NTAServices.CreateDockableForm(GDockForm) as TForm;
  if GDockHost <> nil then
    GDockHost.OnDestroy := GDockFormObj.HostDestroyed;
end;

procedure ShowDepTreeWindow;
begin
  try
    EnsureDockForm;
    if GDockHost <> nil then
    begin
      GDockHost.Show;
      GDockHost.BringToFront;
      RefreshDepTreeWindow;
    end;
  except
    on E: Exception do
      MessageDlg('Dependency Tree failed to open: ' + E.Message, mtError, [mbOK], 0);
  end;
end;

procedure RefreshDepTreeWindow;
begin
  try
    if GFrame <> nil then
      GFrame.RefreshTree;
  except
    on E: Exception do
      if GFrame <> nil then
        GFrame.SetStatus('Refresh failed: ' + E.Message);
  end;
end;

function IsDepTreeWindowVisible: Boolean;
begin
  Result := (GDockHost <> nil) and GDockHost.Visible;
end;

initialization

finalization
  UnregisterDepTreeDockForm;
  GFrame := nil;
  GDockHost := nil;
  GDockForm := nil;
  GDockFormObj := nil;

end.
