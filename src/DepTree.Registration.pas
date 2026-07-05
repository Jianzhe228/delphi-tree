unit DepTree.Registration;

interface

procedure Register;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Menus,
  ToolsAPI,
  DepTree.DockForm,
  DepTree.Notifiers;

type
  TDepTreeMenuHandler = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    procedure MenuClick(Sender: TObject);
  end;

var
  GMenuItem: TMenuItem;
  GMenuHandler: TDepTreeMenuHandler;
  GNotifier: IOTAIDENotifier;
  GNotifierIndex: Integer = -1;

function PlainCaption(const ACaption: string): string;
begin
  Result := StringReplace(ACaption, '&', '', [rfReplaceAll]);
end;

function FindViewMenu(AMainMenu: TMainMenu): TMenuItem;
var
  Index: Integer;
begin
  Result := nil;
  if AMainMenu = nil then
    Exit;

  for Index := 0 to AMainMenu.Items.Count - 1 do
  begin
    if SameText(PlainCaption(AMainMenu.Items[Index].Caption), 'View') or
      SameText(AMainMenu.Items[Index].Name, 'ViewMenu') then
      Exit(AMainMenu.Items[Index]);
  end;
end;

procedure TDepTreeMenuHandler.MenuClick(Sender: TObject);
begin
  ShowDepTreeWindow;
end;

procedure TDepTreeMenuHandler.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = GMenuItem) then
    GMenuItem := nil;
end;

procedure InstallMenu;
var
  NTAServices: INTAServices;
  MainMenu: TMainMenu;
  ParentMenu: TMenuItem;
begin
  if GMenuItem <> nil then
    Exit;

  if not Supports(BorlandIDEServices, INTAServices, NTAServices) then
    Exit;

  MainMenu := NTAServices.MainMenu;
  if MainMenu = nil then
    Exit;

  ParentMenu := FindViewMenu(MainMenu);
  if ParentMenu = nil then
    ParentMenu := MainMenu.Items;

  GMenuItem := TMenuItem.Create(nil);
  GMenuItem.Caption := 'Project Source Tree';
  GMenuHandler := TDepTreeMenuHandler.Create(nil);
  GMenuItem.FreeNotification(GMenuHandler);
  GMenuItem.OnClick := GMenuHandler.MenuClick;
  ParentMenu.Add(GMenuItem);
end;

procedure UninstallMenu;
begin
  if GMenuItem <> nil then
  begin
    GMenuItem.OnClick := nil;
    try
      if GMenuItem.Parent <> nil then
        GMenuItem.Parent.Remove(GMenuItem);
      FreeAndNil(GMenuItem);
    except
      GMenuItem := nil;
    end;
  end;
  FreeAndNil(GMenuHandler);
end;

procedure InstallNotifier;
var
  Services: IOTAServices;
begin
  if GNotifierIndex >= 0 then
    Exit;

  if not Supports(BorlandIDEServices, IOTAServices, Services) then
    Exit;

  GNotifier := TDepTreeIDENotifier.Create;
  GNotifierIndex := Services.AddNotifier(GNotifier);
end;

procedure UninstallNotifier;
var
  Services: IOTAServices;
begin
  if GNotifierIndex < 0 then
    Exit;

  try
    if Supports(BorlandIDEServices, IOTAServices, Services) then
      Services.RemoveNotifier(GNotifierIndex);
  except
    // During IDE shutdown the service container can be partially torn down.
  end;
  GNotifierIndex := -1;
  GNotifier := nil;
end;

procedure Register;
begin
  RegisterDepTreeDockForm;
  InstallMenu;
  InstallNotifier;
end;

initialization

finalization
  try
    UninstallNotifier;
  except
  end;
  try
    UninstallMenu;
  except
  end;
  try
    UnregisterDepTreeDockForm;
  except
  end;

end.
