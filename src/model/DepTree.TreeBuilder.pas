unit DepTree.TreeBuilder;

interface

uses
  System.SysUtils,
  DepTree.Model;

type
  TDepTreeItem = class
  public
    NodeId: string;
    DisplayName: string;
    FileName: string;
    Caption: string;
    Kind: TDepTreeNodeKind;
    Section: TDepTreeDependencySection;
    UsesLine: Integer;
    Flags: TDepTreeDependencyFlags;
    Ancestors: TArray<string>;

    constructor CreateFromNode(ANode: TDepTreeNode;
      ASection: TDepTreeDependencySection; AUsesLine: Integer;
      const AAncestors: TArray<string>; AFlags: TDepTreeDependencyFlags);
  end;

implementation

function FormatCaption(ANode: TDepTreeNode; ASection: TDepTreeDependencySection;
  AFlags: TDepTreeDependencyFlags): string;
var
  Suffix: string;
begin
  if ANode = nil then
    Exit('(missing)');

  if ANode.DisplayName <> '' then
    Result := ANode.DisplayName
  else if ANode.FileName <> '' then
    Result := ChangeFileExt(ExtractFileName(ANode.FileName), '')
  else
    Result := ANode.Id;

  Suffix := '';
  if dfCycle in AFlags then
    Suffix := Suffix + ' (cycle)';
  if dfShared in AFlags then
    Suffix := Suffix + ' (shared)';
  if dfExternal in AFlags then
    Suffix := Suffix + ' (external)';
  if dfMissing in AFlags then
    Suffix := Suffix + ' (missing)';

  if ASection = dsImplementation then
    Result := Result + ' [impl]';

  Result := Result + Suffix;
end;

{ TDepTreeItem }

constructor TDepTreeItem.CreateFromNode(ANode: TDepTreeNode;
  ASection: TDepTreeDependencySection; AUsesLine: Integer;
  const AAncestors: TArray<string>; AFlags: TDepTreeDependencyFlags);
begin
  inherited Create;
  if ANode <> nil then
  begin
    NodeId := ANode.Id;
    DisplayName := ANode.DisplayName;
    FileName := ANode.FileName;
    Kind := ANode.Kind;
  end
  else
    Kind := dnMissing;

  Section := ASection;
  UsesLine := AUsesLine;
  Ancestors := Copy(AAncestors);
  Flags := AFlags;
  Caption := FormatCaption(ANode, ASection, AFlags);
end;

end.
