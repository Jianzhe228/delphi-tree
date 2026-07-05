unit DepTree.ShellIcons;

interface

uses
  Vcl.Controls;

function GetShellImageList: TImageList;
function ShellIconIndexForFile(const AFileName: string): Integer;
function ShellIconIndexForFolder: Integer;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.SysUtils,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.Graphics;

const
  IconSize = 16;
  MaskColor: TColor = $00FF00FF;

var
  GImageList: TImageList;
  GIconIndexByKey: TDictionary<string, Integer>;

function EnsureImageList: TImageList;
begin
  if GImageList = nil then
  begin
    GImageList := TImageList.Create(Application);
    GImageList.Width := IconSize;
    GImageList.Height := IconSize;
  end;
  Result := GImageList;
end;

function AddIconHandleToList(AIcon: HICON): Integer;
var
  Bitmap: TBitmap;
  R: TRect;
begin
  Result := -1;
  if AIcon = 0 then
    Exit;

  Bitmap := TBitmap.Create;
  try
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(IconSize, IconSize);
    R.Left := 0;
    R.Top := 0;
    R.Right := IconSize;
    R.Bottom := IconSize;
    Bitmap.Canvas.Brush.Color := MaskColor;
    Bitmap.Canvas.FillRect(R);
    DrawIconEx(Bitmap.Canvas.Handle, 0, 0, AIcon, IconSize, IconSize, 0, 0, DI_NORMAL);
    Result := EnsureImageList.AddMasked(Bitmap, MaskColor);
  finally
    Bitmap.Free;
  end;
end;

function FetchIconIndexForKey(const AProbePath: string; AAttributes: Cardinal): Integer;
var
  FileInfo: TSHFileInfo;
begin
  Result := -1;
  FillChar(FileInfo, SizeOf(FileInfo), 0);
  if SHGetFileInfo(PChar(AProbePath), AAttributes, FileInfo, SizeOf(FileInfo),
    SHGFI_ICON or SHGFI_SMALLICON or SHGFI_USEFILEATTRIBUTES) = 0 then
    Exit;
  try
    Result := AddIconHandleToList(FileInfo.hIcon);
  finally
    DestroyIcon(FileInfo.hIcon);
  end;
end;

function IndexForKey(const AKey, AProbePath: string; AAttributes: Cardinal): Integer;
begin
  EnsureImageList;
  if GIconIndexByKey = nil then
    GIconIndexByKey := TDictionary<string, Integer>.Create;

  if not GIconIndexByKey.TryGetValue(AKey, Result) then
  begin
    Result := FetchIconIndexForKey(AProbePath, AAttributes);
    GIconIndexByKey.Add(AKey, Result);
  end;
end;

function GetShellImageList: TImageList;
begin
  Result := EnsureImageList;
end;

function ShellIconIndexForFolder: Integer;
begin
  Result := IndexForKey('\folder', 'folder', FILE_ATTRIBUTE_DIRECTORY);
end;

function ShellIconIndexForFile(const AFileName: string): Integer;
var
  Ext: string;
begin
  Ext := AnsiLowerCase(ExtractFileExt(AFileName));
  if Ext = '' then
    Ext := '.pas';
  Result := IndexForKey(Ext, 'X' + Ext, FILE_ATTRIBUTE_NORMAL);
end;

initialization

finalization
  FreeAndNil(GIconIndexByKey);
  GImageList := nil;

end.
