unit DepTree.ViewController;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.Menus,
  DepTree.Model,
  DepTree.TreeBuilder;

type
  TDepTreeViewController = class
  private
    FTree: TTreeView;
    FGraph: TDepTreeGraph;
    FItems: TObjectList<TDepTreeItem>;
    FProject: TDepTreeProjectInfo;
    FHideExternal: Boolean;
    FLastStatus: string;
    FOnStatusChanged: TNotifyEvent;
    FPopupMenu: TPopupMenu;
    FNewMenuItem: TMenuItem;
    FDeleteMenuItem: TMenuItem;

    procedure AddTreeNode(AParent: TTreeNode; AItem: TDepTreeItem);
    procedure ClearTree;
    procedure RebuildTree;
    procedure RebuildContainsTree;
    function NodeSortText(ANode: TDepTreeNode): string;
    function NodePathKey(ANode: TTreeNode): string;
    function NodeFolderPath(ANode: TTreeNode): string;
    procedure CaptureExpandState(ANode: TTreeNode; AExpanded: TList<string>);
    procedure RestoreExpandState(ANode: TTreeNode; AExpanded: TList<string>);
    procedure SetStatus(const AStatus: string);

    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeHint(Sender: TObject; const Node: TTreeNode; var Hint: string);
    procedure TreeMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PopupMenuPopup(Sender: TObject);
    procedure NewFileClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  public
    constructor Create(ATree: TTreeView);
    destructor Destroy; override;

    procedure RefreshFromIDE;
    procedure SetHideExternal(AHideExternal: Boolean);
    procedure OpenSelected;

    property LastStatus: string read FLastStatus;
    property OnStatusChanged: TNotifyEvent read FOnStatusChanged write FOnStatusChanged;
  end;

implementation

uses
  Winapi.Windows,
  System.Generics.Defaults,
  Vcl.Dialogs,
  DepTree.ProjectAnalyzer,
  DepTree.OTAUtils,
  DepTree.ShellIcons;

{ TDepTreeViewController }

constructor TDepTreeViewController.Create(ATree: TTreeView);
const
  CNewFileCaptions: array[TDepTreeNewFileKind] of string =
    ('VCL Form...', 'VCL Frame...', 'Data Module...', 'Unit...');
var
  Kind: TDepTreeNewFileKind;
  KindItem: TMenuItem;
begin
  inherited Create;
  FTree := ATree;
  FItems := TObjectList<TDepTreeItem>.Create(True);
  FHideExternal := True;

  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.OnDblClick := TreeDblClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnHint := TreeHint;
  FTree.OnMouseDown := TreeMouseDown;

  FPopupMenu := TPopupMenu.Create(nil);
  FPopupMenu.OnPopup := PopupMenuPopup;

  FNewMenuItem := TMenuItem.Create(nil);
  FNewMenuItem.Caption := 'New';
  FPopupMenu.Items.Add(FNewMenuItem);

  for Kind := Low(TDepTreeNewFileKind) to High(TDepTreeNewFileKind) do
  begin
    KindItem := TMenuItem.Create(nil);
    KindItem.Caption := CNewFileCaptions[Kind];
    KindItem.Tag := Ord(Kind);
    KindItem.OnClick := NewFileClick;
    FNewMenuItem.Add(KindItem);
  end;

  FDeleteMenuItem := TMenuItem.Create(nil);
  FDeleteMenuItem.Caption := 'Delete';
  FDeleteMenuItem.OnClick := DeleteClick;
  FPopupMenu.Items.Add(FDeleteMenuItem);

  FTree.PopupMenu := FPopupMenu;
end;

destructor TDepTreeViewController.Destroy;
begin
  FPopupMenu.Free;
  FGraph.Free;
  FItems.Free;
  inherited;
end;

procedure TDepTreeViewController.ClearTree;
begin
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    FItems.Clear;
  finally
    FTree.Items.EndUpdate;
  end;
end;

procedure TDepTreeViewController.RefreshFromIDE;
var
  Root: TTreeNode;
begin
  FreeAndNil(FGraph);
  FProject := Default(TDepTreeProjectInfo);

  if not ReadActiveProjectInfo(FProject) then
  begin
    ClearTree;
    Root := FTree.Items.Add(nil, 'No active Delphi project');
    Root.StateIndex := -1;
    FLastStatus := 'No active Delphi project.';
    Exit;
  end;

  try
    FGraph := TDepTreeProjectAnalyzer.BuildGraph(
      FProject,
      function(const AFileName: string): string
      begin
        Result := ReadSourceText(AFileName);
      end);
    RebuildTree;
    FLastStatus := Format('Loaded %s.', [FProject.ProjectName]);
  except
    on E: Exception do
    begin
      ClearTree;
      FTree.Items.Add(nil, 'Dependency analysis failed: ' + E.Message);
      FLastStatus := E.Message;
    end;
  end;
end;

function TDepTreeViewController.NodePathKey(ANode: TTreeNode): string;
begin
  Result := '';
  while (ANode <> nil) and (ANode.Parent <> nil) do
  begin
    if Result = '' then
      Result := ANode.Text
    else
      Result := ANode.Text + '/' + Result;
    ANode := ANode.Parent;
  end;
end;

function TDepTreeViewController.NodeFolderPath(ANode: TTreeNode): string;
var
  RelativePath: string;
begin
  if (ANode <> nil) and (ANode.Data <> nil) then
    Exit(ExtractFileDir(TDepTreeItem(ANode.Data).FileName));

  RelativePath := '';
  while (ANode <> nil) and (ANode.Parent <> nil) do
  begin
    if RelativePath = '' then
      RelativePath := ANode.Text
    else
      RelativePath := ANode.Text + PathDelim + RelativePath;
    ANode := ANode.Parent;
  end;

  if RelativePath = '' then
    Result := FProject.ProjectDir
  else
    Result := ExpandFileName(IncludeTrailingPathDelimiter(FProject.ProjectDir) + RelativePath);
end;

procedure TDepTreeViewController.CaptureExpandState(ANode: TTreeNode; AExpanded: TList<string>);
var
  Index: Integer;
begin
  if ANode = nil then
    Exit;

  if ANode.Expanded then
    AExpanded.Add(NodePathKey(ANode));
  for Index := 0 to ANode.Count - 1 do
    CaptureExpandState(ANode.Item[Index], AExpanded);
end;

procedure TDepTreeViewController.RestoreExpandState(ANode: TTreeNode; AExpanded: TList<string>);
var
  Index: Integer;
begin
  if ANode = nil then
    Exit;

  if AExpanded.IndexOf(NodePathKey(ANode)) >= 0 then
    ANode.Expand(False);
  for Index := 0 to ANode.Count - 1 do
    RestoreExpandState(ANode.Item[Index], AExpanded);
end;

procedure TDepTreeViewController.RebuildTree;
var
  ExpandedPaths: TList<string>;
  Index: Integer;
begin
  ExpandedPaths := TList<string>.Create;
  try
    for Index := 0 to FTree.Items.Count - 1 do
      if FTree.Items[Index].Parent = nil then
        CaptureExpandState(FTree.Items[Index], ExpandedPaths);

    FTree.Items.BeginUpdate;
    try
      FTree.Items.Clear;
      FItems.Clear;

      if FGraph = nil then
        Exit;

      RebuildContainsTree;
    finally
      FTree.Items.EndUpdate;
    end;

    for Index := 0 to FTree.Items.Count - 1 do
      if FTree.Items[Index].Parent = nil then
        RestoreExpandState(FTree.Items[Index], ExpandedPaths);
  finally
    ExpandedPaths.Free;
  end;
end;

function RelativeDisplayPath(const ABaseDir, AFileName: string): string;
var
  BaseDir: string;
begin
  if ABaseDir <> '' then
  begin
    BaseDir := IncludeTrailingPathDelimiter(ExpandFileName(ABaseDir));
    Result := ExtractRelativePath(BaseDir, ExpandFileName(AFileName))
  end
  else
    Result := ExtractFileName(AFileName);

  Result := StringReplace(Result, '/', PathDelim, [rfReplaceAll]);
end;

function TDepTreeViewController.NodeSortText(ANode: TDepTreeNode): string;
begin
  if ANode = nil then
    Exit('');
  Result := RelativeDisplayPath(FProject.ProjectDir, ANode.FileName);
end;

procedure TDepTreeViewController.RebuildContainsTree;
var
  Nodes: TList<TDepTreeNode>;
  GraphNode: TDepTreeNode;
  RootNode: TTreeNode;
  ParentNode: TTreeNode;
  FolderNode: TTreeNode;
  Parts: TStringList;
  RelativePath: string;
  Index: Integer;
  Item: TDepTreeItem;
  FolderChildren: TObjectDictionary<string, TDictionary<string, Boolean>>;
  FolderHasFile: TDictionary<string, Boolean>;
  FolderNodesByKey: TDictionary<string, TTreeNode>;
  ParentKey: string;
  RunLabel: string;
  RunKey: string;

  procedure NoteFolderChild(const AParentKey, AChildName: string);
  var
    Children: TDictionary<string, Boolean>;
  begin
    if not FolderChildren.TryGetValue(AParentKey, Children) then
    begin
      Children := TDictionary<string, Boolean>.Create;
      FolderChildren.Add(AParentKey, Children);
    end;
    Children.AddOrSetValue(AChildName, True);
  end;

  function ChildCount(const AKey: string): Integer;
  var
    Children: TDictionary<string, Boolean>;
  begin
    if FolderChildren.TryGetValue(AKey, Children) then
      Result := Children.Count
    else
      Result := 0;
  end;

  function HasDirectFile(const AKey: string): Boolean;
  begin
    Result := FolderHasFile.ContainsKey(AKey);
  end;

begin
  if FGraph = nil then
    Exit;

  if FProject.ProjectName <> '' then
    RootNode := FTree.Items.Add(nil, FProject.ProjectName)
  else
    RootNode := FTree.Items.Add(nil, 'Project');
  RootNode.ImageIndex := ShellIconIndexForFile(FProject.ProjectFile);
  RootNode.SelectedIndex := RootNode.ImageIndex;

  Nodes := TList<TDepTreeNode>.Create;
  Parts := TStringList.Create;
  FolderChildren := TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  FolderHasFile := TDictionary<string, Boolean>.Create;
  FolderNodesByKey := TDictionary<string, TTreeNode>.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := PathDelim;

    for GraphNode in FGraph.AllNodes do
    begin
      if GraphNode.FileName = '' then
        Continue;
      if FHideExternal and (GraphNode.Kind in [dnExternal, dnMissing]) then
        Continue;
      if GraphNode.Kind = dnExternal then
        Continue;

      Nodes.Add(GraphNode);
    end;

    Nodes.Sort(TComparer<TDepTreeNode>.Construct(
      function(const ALeft, ARight: TDepTreeNode): Integer
      begin
        Result := CompareText(NodeSortText(ALeft), NodeSortText(ARight));
      end));

    // Pass 1: learn the folder shape (child-folder-name sets, and which folders hold a file directly)
    for GraphNode in Nodes do
    begin
      RelativePath := RelativeDisplayPath(FProject.ProjectDir, GraphNode.FileName);
      Parts.DelimitedText := RelativePath;
      if Parts.Count = 0 then
        Continue;

      ParentKey := '';
      for Index := 0 to Parts.Count - 2 do
      begin
        NoteFolderChild(ParentKey, Parts[Index]);
        if ParentKey = '' then
          ParentKey := Parts[Index]
        else
          ParentKey := ParentKey + PathDelim + Parts[Index];
      end;
      if Parts.Count > 1 then
        FolderHasFile.AddOrSetValue(ParentKey, True);
    end;

    // Pass 2: build the tree, merging runs of single-child, file-less folders into one node
    for GraphNode in Nodes do
    begin
      RelativePath := RelativeDisplayPath(FProject.ProjectDir, GraphNode.FileName);
      Parts.DelimitedText := RelativePath;
      if Parts.Count = 0 then
        Continue;

      ParentNode := RootNode;
      ParentKey := '';
      Index := 0;
      while Index <= Parts.Count - 2 do
      begin
        RunLabel := Parts[Index];
        if ParentKey = '' then
          RunKey := Parts[Index]
        else
          RunKey := ParentKey + PathDelim + Parts[Index];
        Inc(Index);

        while (Index <= Parts.Count - 2) and (ChildCount(RunKey) = 1)
          and not HasDirectFile(RunKey) do
        begin
          RunLabel := RunLabel + PathDelim + Parts[Index];
          RunKey := RunKey + PathDelim + Parts[Index];
          Inc(Index);
        end;

        if not FolderNodesByKey.TryGetValue(RunKey, FolderNode) then
        begin
          FolderNode := FTree.Items.AddChild(ParentNode, RunLabel);
          FolderNode.ImageIndex := ShellIconIndexForFolder;
          FolderNode.SelectedIndex := FolderNode.ImageIndex;
          FolderNodesByKey.Add(RunKey, FolderNode);
        end;
        ParentNode := FolderNode;
        ParentKey := RunKey;
      end;

      Item := TDepTreeItem.CreateFromNode(GraphNode, dsUnknown, 0, nil, []);
      Item.Caption := Parts[Parts.Count - 1];
      if GraphNode.Kind = dnMissing then
        Item.Caption := Item.Caption + ' (missing)';
      AddTreeNode(ParentNode, Item);
    end;

    RootNode.Expand(False);
  finally
    FolderNodesByKey.Free;
    FolderHasFile.Free;
    FolderChildren.Free;
    Parts.Free;
    Nodes.Free;
  end;
end;

procedure TDepTreeViewController.AddTreeNode(AParent: TTreeNode; AItem: TDepTreeItem);
var
  Node: TTreeNode;
begin
  if AItem = nil then
    Exit;

  Node := FTree.Items.AddChildObject(AParent, AItem.Caption, AItem);
  Node.ImageIndex := ShellIconIndexForFile(AItem.FileName);
  Node.SelectedIndex := Node.ImageIndex;
  FItems.Add(AItem);
end;

procedure TDepTreeViewController.TreeDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TDepTreeViewController.TreeKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end;
end;

procedure TDepTreeViewController.TreeHint(Sender: TObject; const Node: TTreeNode;
  var Hint: string);
var
  Item: TDepTreeItem;
begin
  if (Node = nil) or (Node.Data = nil) then
    Exit;

  Item := TDepTreeItem(Node.Data);
  if Item.FileName <> '' then
    Hint := Item.FileName
  else
    Hint := DepTreeNodeKindToString(Item.Kind);
end;

procedure TDepTreeViewController.TreeMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Node: TTreeNode;
begin
  if Button = mbRight then
  begin
    Node := FTree.GetNodeAt(X, Y);
    if Node <> nil then
      FTree.Selected := Node;
  end;
end;

procedure TDepTreeViewController.PopupMenuPopup(Sender: TObject);
begin
  FDeleteMenuItem.Enabled := (FTree.Selected <> nil) and (FTree.Selected.Data <> nil);
end;

procedure TDepTreeViewController.NewFileClick(Sender: TObject);
const
  CTitles: array[TDepTreeNewFileKind] of string =
    ('New VCL Form', 'New VCL Frame', 'New Data Module', 'New Unit');
  CNamePrompts: array[TDepTreeNewFileKind] of string =
    ('Form name:', 'Frame name:', 'Data module name:', '');
  CDefaultNames: array[TDepTreeNewFileKind] of string =
    ('Form1', 'Frame1', 'DataModule1', '');
var
  Kind: TDepTreeNewFileKind;
  TargetDir: string;
  UnitName: string;
  FormName: string;
  NewFileName: string;
  Values: array[0..1] of string;
begin
  Kind := TDepTreeNewFileKind(TMenuItem(Sender).Tag);
  TargetDir := NodeFolderPath(FTree.Selected);

  if Kind = nfUnit then
  begin
    UnitName := 'Unit1';
    FormName := '';
    if not InputQuery(CTitles[Kind], 'Unit name:', UnitName) then
      Exit;
  end
  else
  begin
    Values[0] := 'Unit1';
    Values[1] := CDefaultNames[Kind];
    if not InputQuery(CTitles[Kind], ['Unit name:', CNamePrompts[Kind]], Values) then
      Exit;
    UnitName := Values[0];
    FormName := Values[1];
  end;

  UnitName := Trim(UnitName);
  if not IsValidIdent(UnitName, True) then
  begin
    SetStatus('Invalid unit name: ' + UnitName);
    Exit;
  end;

  if Kind <> nfUnit then
  begin
    FormName := Trim(FormName);
    if not IsValidIdent(FormName) then
    begin
      SetStatus('Invalid name: ' + FormName);
      Exit;
    end;
    // The generated class ("T" + name) and variable would collide with the
    // unit's own identifier (E2004).
    if SameText(FormName, UnitName) or SameText('T' + FormName, UnitName) then
    begin
      SetStatus('The name must differ from the unit name: ' + FormName);
      Exit;
    end;
  end;

  if not CreateNewProjectFile(Kind, TargetDir, UnitName, FormName, NewFileName) then
  begin
    SetStatus('Could not create ' + UnitName + '.pas - it may already exist there.');
    Exit;
  end;

  RefreshFromIDE;
  OpenFileInIDE(NewFileName);
end;

procedure TDepTreeViewController.DeleteClick(Sender: TObject);
var
  Item: TDepTreeItem;
  Description: string;
begin
  if (FTree.Selected = nil) or (FTree.Selected.Data = nil) then
    Exit;

  Item := TDepTreeItem(FTree.Selected.Data);
  if Item.FileName = '' then
    Exit;

  Description := ExtractFileName(Item.FileName);
  if FileExists(ChangeFileExt(Item.FileName, '.dfm')) then
    Description := Description + ' (and its .dfm)';

  if MessageDlg('Delete ' + Description +
    '?'#13#10#13#10'The file(s) will be removed from the project and sent to the Recycle Bin.',
    mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if DeleteProjectFile(Item.FileName) then
    RefreshFromIDE
  else
    SetStatus('Could not delete: ' + Item.FileName);
end;

procedure TDepTreeViewController.SetHideExternal(AHideExternal: Boolean);
begin
  if FHideExternal = AHideExternal then
    Exit;
  FHideExternal := AHideExternal;
  RebuildTree;
end;

procedure TDepTreeViewController.SetStatus(const AStatus: string);
begin
  FLastStatus := AStatus;
  if Assigned(FOnStatusChanged) then
    FOnStatusChanged(Self);
end;

procedure TDepTreeViewController.OpenSelected;
var
  Item: TDepTreeItem;
begin
  if (FTree.Selected = nil) or (FTree.Selected.Data = nil) then
    Exit;

  Item := TDepTreeItem(FTree.Selected.Data);
  if Item.FileName = '' then
    Exit;

  if not FileExists(Item.FileName) then
  begin
    SetStatus('File not found: ' + Item.FileName);
    Exit;
  end;

  if not OpenFileInIDE(Item.FileName, Item.UsesLine) then
    SetStatus('Could not open: ' + Item.FileName);
end;

end.
