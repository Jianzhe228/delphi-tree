unit DepTree.Model;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TDepTreeNodeKind = (
    dnProject,
    dnUnit,
    dnFormUnit,
    dnPackage,
    dnInclude,
    dnExternal,
    dnMissing
  );

  TDepTreeDependencySection = (
    dsUnknown,
    dsInterface,
    dsImplementation
  );

  TDepTreeDependencyFlag = (
    dfCycle,
    dfShared,
    dfExternal,
    dfMissing
  );

  TDepTreeDependencyFlags = set of TDepTreeDependencyFlag;

  TUsesRef = record
    UnitName: string;
    ExplicitPath: string;
    Section: TDepTreeDependencySection;
    Line: Integer;
    class function Create(const AUnitName, AExplicitPath: string;
      ASection: TDepTreeDependencySection; ALine: Integer): TUsesRef; static;
  end;

  TUsesRefArray = TArray<TUsesRef>;

  TDepTreeProjectInfo = record
    ProjectName: string;
    ProjectFile: string;
    ProjectDir: string;
    MainSource: string;
    UnitSearchPaths: TArray<string>;
    SourceFiles: TArray<string>;
  end;

  TDepTreeNode = class
  private
    FId: string;
    FDisplayName: string;
    FFileName: string;
    FKind: TDepTreeNodeKind;
  public
    constructor Create(const AId, ADisplayName, AFileName: string;
      AKind: TDepTreeNodeKind);

    property Id: string read FId;
    property DisplayName: string read FDisplayName write FDisplayName;
    property FileName: string read FFileName write FFileName;
    property Kind: TDepTreeNodeKind read FKind write FKind;
  end;

  TDepTreeEdge = record
    FromId: string;
    ToId: string;
    Section: TDepTreeDependencySection;
    UsesLine: Integer;
    class function Create(const AFromId, AToId: string;
      ASection: TDepTreeDependencySection; AUsesLine: Integer): TDepTreeEdge; static;
  end;

  TDepTreeGraph = class
  private
    FNodesById: TObjectDictionary<string, TDepTreeNode>;
    FEdges: TList<TDepTreeEdge>;
    function EdgeExists(const AFromId, AToId: string;
      ASection: TDepTreeDependencySection): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    class function MakeNodeId(const AUnitName, AFileName: string): string; static;

    function EnsureNode(const AUnitName, AFileName: string;
      AKind: TDepTreeNodeKind): TDepTreeNode;
    function FindNode(const AId: string): TDepTreeNode;
    function AllNodes: TArray<TDepTreeNode>;

    procedure AddEdge(const AFromId, AToId: string;
      ASection: TDepTreeDependencySection; AUsesLine: Integer);

    function OutEdges(const ANodeId: string): TArray<TDepTreeEdge>;
    function InEdges(const ANodeId: string): TArray<TDepTreeEdge>;
    function InDegree(const ANodeId: string): Integer;
  end;

function DepTreeNodeKindToString(AKind: TDepTreeNodeKind): string;
function DepTreeSectionToString(ASection: TDepTreeDependencySection): string;

// Canonical case-insensitive key for a file path; every map that is keyed by
// file name (graph nodes, parse cache, editor-text snapshots) must use this.
function DepTreeNormalizeFileKey(const AFileName: string): string;

implementation

function DepTreeNormalizeFileKey(const AFileName: string): string;
begin
  if AFileName = '' then
    Exit('');

  Result := AnsiLowerCase(ExpandFileName(AFileName));
end;

function DepTreeNodeKindToString(AKind: TDepTreeNodeKind): string;
begin
  case AKind of
    dnProject:
      Result := 'project';
    dnUnit:
      Result := 'unit';
    dnFormUnit:
      Result := 'form';
    dnPackage:
      Result := 'package';
    dnInclude:
      Result := 'include';
    dnExternal:
      Result := 'external';
    dnMissing:
      Result := 'missing';
  else
    Result := 'unknown';
  end;
end;

function DepTreeSectionToString(ASection: TDepTreeDependencySection): string;
begin
  case ASection of
    dsInterface:
      Result := 'interface';
    dsImplementation:
      Result := 'implementation';
  else
    Result := 'unknown';
  end;
end;

{ TUsesRef }

class function TUsesRef.Create(const AUnitName, AExplicitPath: string;
  ASection: TDepTreeDependencySection; ALine: Integer): TUsesRef;
begin
  Result.UnitName := AUnitName;
  Result.ExplicitPath := AExplicitPath;
  Result.Section := ASection;
  Result.Line := ALine;
end;

{ TDepTreeNode }

constructor TDepTreeNode.Create(const AId, ADisplayName, AFileName: string;
  AKind: TDepTreeNodeKind);
begin
  inherited Create;
  FId := AId;
  FDisplayName := ADisplayName;
  FFileName := AFileName;
  FKind := AKind;
end;

{ TDepTreeEdge }

class function TDepTreeEdge.Create(const AFromId, AToId: string;
  ASection: TDepTreeDependencySection; AUsesLine: Integer): TDepTreeEdge;
begin
  Result.FromId := AFromId;
  Result.ToId := AToId;
  Result.Section := ASection;
  Result.UsesLine := AUsesLine;
end;

{ TDepTreeGraph }

constructor TDepTreeGraph.Create;
begin
  inherited Create;
  FNodesById := TObjectDictionary<string, TDepTreeNode>.Create([doOwnsValues]);
  FEdges := TList<TDepTreeEdge>.Create;
end;

destructor TDepTreeGraph.Destroy;
begin
  FEdges.Free;
  FNodesById.Free;
  inherited;
end;

class function TDepTreeGraph.MakeNodeId(const AUnitName, AFileName: string): string;
begin
  if Trim(AFileName) <> '' then
    Result := 'file:' + DepTreeNormalizeFileKey(AFileName)
  else
    Result := 'unit:' + AnsiLowerCase(Trim(AUnitName));
end;

function TDepTreeGraph.EnsureNode(const AUnitName, AFileName: string;
  AKind: TDepTreeNodeKind): TDepTreeNode;
var
  Id: string;
begin
  Id := MakeNodeId(AUnitName, AFileName);
  if not FNodesById.TryGetValue(Id, Result) then
  begin
    Result := TDepTreeNode.Create(Id, AUnitName, AFileName, AKind);
    FNodesById.Add(Id, Result);
    Exit;
  end;

  if (Result.DisplayName = '') and (AUnitName <> '') then
    Result.DisplayName := AUnitName;
  if (Result.FileName = '') and (AFileName <> '') then
    Result.FileName := AFileName;
  if (Result.Kind in [dnMissing, dnExternal]) and not (AKind in [dnMissing, dnExternal]) then
    Result.Kind := AKind;
end;

function TDepTreeGraph.FindNode(const AId: string): TDepTreeNode;
begin
  if not FNodesById.TryGetValue(AId, Result) then
    Result := nil;
end;

function TDepTreeGraph.AllNodes: TArray<TDepTreeNode>;
var
  Pair: TPair<string, TDepTreeNode>;
  Index: Integer;
begin
  SetLength(Result, FNodesById.Count);
  Index := 0;
  for Pair in FNodesById do
  begin
    Result[Index] := Pair.Value;
    Inc(Index);
  end;
end;

function TDepTreeGraph.EdgeExists(const AFromId, AToId: string;
  ASection: TDepTreeDependencySection): Boolean;
var
  Edge: TDepTreeEdge;
begin
  Result := False;
  for Edge in FEdges do
  begin
    if SameText(Edge.FromId, AFromId) and SameText(Edge.ToId, AToId) and
      (Edge.Section = ASection) then
      Exit(True);
  end;
end;

procedure TDepTreeGraph.AddEdge(const AFromId, AToId: string;
  ASection: TDepTreeDependencySection; AUsesLine: Integer);
begin
  if (AFromId = '') or (AToId = '') then
    Exit;

  if EdgeExists(AFromId, AToId, ASection) then
    Exit;

  FEdges.Add(TDepTreeEdge.Create(AFromId, AToId, ASection, AUsesLine));
end;

function TDepTreeGraph.OutEdges(const ANodeId: string): TArray<TDepTreeEdge>;
var
  Edge: TDepTreeEdge;
  Count: Integer;
begin
  Result := nil;
  Count := 0;
  for Edge in FEdges do
  begin
    if SameText(Edge.FromId, ANodeId) then
    begin
      SetLength(Result, Count + 1);
      Result[Count] := Edge;
      Inc(Count);
    end;
  end;
end;

function TDepTreeGraph.InEdges(const ANodeId: string): TArray<TDepTreeEdge>;
var
  Edge: TDepTreeEdge;
  Count: Integer;
begin
  Result := nil;
  Count := 0;
  for Edge in FEdges do
  begin
    if SameText(Edge.ToId, ANodeId) then
    begin
      SetLength(Result, Count + 1);
      Result[Count] := Edge;
      Inc(Count);
    end;
  end;
end;

function TDepTreeGraph.InDegree(const ANodeId: string): Integer;
var
  Edge: TDepTreeEdge;
begin
  Result := 0;
  for Edge in FEdges do
  begin
    if SameText(Edge.ToId, ANodeId) then
      Inc(Result);
  end;
end;

end.
