unit DepTree.Notifiers;

interface

uses
  ToolsAPI;

type
  TDepTreeIDENotifier = class(TNotifierObject, IOTAIDENotifier)
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
    procedure AfterCompile(Succeeded: Boolean);
  end;

implementation

uses
  DepTree.DockForm;

{ TDepTreeIDENotifier }

procedure TDepTreeIDENotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
  if not IsDepTreeWindowVisible then
    Exit;

  case NotifyCode of
    ofnActiveProjectChanged,
    ofnPackageInstalled,
    ofnPackageUninstalled:
      RefreshDepTreeWindow;
  end;
end;

procedure TDepTreeIDENotifier.BeforeCompile(const Project: IOTAProject;
  var Cancel: Boolean);
begin
end;

procedure TDepTreeIDENotifier.AfterCompile(Succeeded: Boolean);
begin
end;

end.
