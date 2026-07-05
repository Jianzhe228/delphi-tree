unit DepTree.Frame;

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  DepTree.ShellIcons,
  DepTree.ViewController;

type
  TDepTreeFrame = class(TFrame)
  private
    FTopPanel: TPanel;
    FRefreshButton: TButton;
    FHideExternalCheck: TCheckBox;
    FTree: TTreeView;
    FStatus: TLabel;
    FController: TDepTreeViewController;

    procedure BuildUi;
    procedure RefreshClick(Sender: TObject);
    procedure HideExternalClick(Sender: TObject);
    procedure ControllerStatusChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure RefreshTree;
    procedure SetStatus(const AText: string);
  end;

implementation

{$R *.dfm}

{ TDepTreeFrame }

constructor TDepTreeFrame.Create(AOwner: TComponent);
begin
  inherited;
  Align := alClient;
  BuildUi;
  FController := TDepTreeViewController.Create(FTree);
  FController.OnStatusChanged := ControllerStatusChanged;
  SetStatus('Ready.');
end;

destructor TDepTreeFrame.Destroy;
begin
  if FRefreshButton <> nil then
    FRefreshButton.OnClick := nil;
  if FHideExternalCheck <> nil then
    FHideExternalCheck.OnClick := nil;
  if FTree <> nil then
    FTree.Images := nil;
  if FController <> nil then
    FController.OnStatusChanged := nil;
  FController.Free;
  inherited;
end;

procedure TDepTreeFrame.BuildUi;
begin
  FTopPanel := TPanel.Create(Self);
  FTopPanel.Parent := Self;
  FTopPanel.Align := alTop;
  FTopPanel.Height := 32;
  FTopPanel.BevelOuter := bvNone;

  FRefreshButton := TButton.Create(Self);
  FRefreshButton.Parent := FTopPanel;
  FRefreshButton.Left := 4;
  FRefreshButton.Top := 4;
  FRefreshButton.Width := 72;
  FRefreshButton.Height := 24;
  FRefreshButton.Caption := 'Refresh';
  FRefreshButton.OnClick := RefreshClick;

  FHideExternalCheck := TCheckBox.Create(Self);
  FHideExternalCheck.Parent := FTopPanel;
  FHideExternalCheck.Left := FRefreshButton.Left + FRefreshButton.Width + 8;
  FHideExternalCheck.Top := 7;
  FHideExternalCheck.Width := 112;
  FHideExternalCheck.Caption := 'Hide external';
  FHideExternalCheck.Checked := True;
  FHideExternalCheck.OnClick := HideExternalClick;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AutoSize := False;
  FStatus.Height := 22;
  FStatus.Layout := tlCenter;
  FStatus.Caption := '';

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ShowHint := True;
  FTree.ToolTips := True;
  FTree.Images := GetShellImageList;
end;

procedure TDepTreeFrame.RefreshClick(Sender: TObject);
begin
  RefreshTree;
end;

procedure TDepTreeFrame.HideExternalClick(Sender: TObject);
begin
  FController.SetHideExternal(FHideExternalCheck.Checked);
end;

procedure TDepTreeFrame.ControllerStatusChanged(Sender: TObject);
begin
  SetStatus(FController.LastStatus);
end;

procedure TDepTreeFrame.RefreshTree;
begin
  if FController = nil then
    Exit;

  try
    FController.RefreshFromIDE;
    SetStatus(FController.LastStatus);
  except
    on E: Exception do
      SetStatus('Refresh failed: ' + E.Message);
  end;
end;

procedure TDepTreeFrame.SetStatus(const AText: string);
begin
  if FStatus <> nil then
    FStatus.Caption := AText;
end;

end.
