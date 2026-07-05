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
  System.Classes,
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
  TDepTreeDockableForm = class(TComponent, INTACustomDockableForm)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
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
  end;

var
  GDockForm: INTACustomDockableForm;
  GDockFormObj: TDepTreeDockableForm;
  GDockHost: TForm;
  GFrame: TDepTreeFrame;

function TDepTreeDockableForm.GetCaption: string;
begin
  Result := 'Project Source Tree';
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

procedure TDepTreeDockableForm.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = GDockHost) then
  begin
    GDockHost := nil;
    GFrame := nil;
  end;
end;

procedure DetachDockHost;
var
  Host: TForm;
begin
  Host := GDockHost;
  GDockHost := nil;
  GFrame := nil;

  if Host = nil then
    Exit;

  if GDockFormObj <> nil then
    Host.RemoveFreeNotification(GDockFormObj);
end;

procedure EnsureDockFormObject;
begin
  if GDockForm = nil then
  begin
    GDockFormObj := TDepTreeDockableForm.Create(nil);
    GDockForm := GDockFormObj;
  end;
end;

procedure RegisterDepTreeDockForm;
begin
  // Desktop-state registration is intentionally avoided. The IDE can create
  // and release registered dockable forms during shutdown, which makes package
  // finalization order fragile. We create the tool window explicitly instead.
end;

procedure UnregisterDepTreeDockForm;
begin
  DetachDockHost;
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
    GDockHost.FreeNotification(GDockFormObj);
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
      MessageDlg('Project Source Tree failed to open: ' + E.Message, mtError, [mbOK], 0);
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
  try
    UnregisterDepTreeDockForm;
    GDockForm := nil;
    // The IDE may still release cached interface references during shutdown.
    // Leaving this tiny helper allocated avoids a finalization-time double free.
    GDockFormObj := nil;
  except
  end;

end.
