unit DepTree.UsesLexer;

interface

uses
  System.SysUtils,
  DepTree.Model;

function ExtractUses(const Source: string): TUsesRefArray;
function ExtractModuleName(const Source, FallbackFileName: string): string;

implementation

uses
  System.Generics.Collections;

type
  TTokenKind = (tkNone, tkIdentifier, tkString, tkSymbol);

  TToken = record
    Kind: TTokenKind;
    Text: string;
    Line: Integer;
  end;

function IsIdentifierStart(C: Char): Boolean;
var
  Code: Integer;
begin
  Code := Ord(C);
  Result := (C = '_') or ((Code >= Ord('A')) and (Code <= Ord('Z'))) or
    ((Code >= Ord('a')) and (Code <= Ord('z'))) or (Code > 127);
end;

function IsIdentifierChar(C: Char): Boolean;
var
  Code: Integer;
begin
  Code := Ord(C);
  Result := IsIdentifierStart(C) or ((Code >= Ord('0')) and (Code <= Ord('9'))) or
    (C = '.');
end;

function IsWhiteSpace(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #13) or (C = #10);
end;

function IsLineBreak(C: Char): Boolean;
begin
  Result := (C = #10) or (C = #13);
end;

procedure AdvanceLineAware(const Source: string; var Position, Line: Integer);
begin
  if Source[Position] = #10 then
    Inc(Line);
  Inc(Position);
end;

function ReadToken(const Source: string; var Position, Line: Integer;
  out Token: TToken): Boolean;
var
  Len: Integer;
  Start: Integer;
  C: Char;
  Text: string;
begin
  Len := Length(Source);
  Token.Kind := tkNone;
  Token.Text := '';
  Token.Line := Line;

  while Position <= Len do
  begin
    C := Source[Position];

    if IsWhiteSpace(C) then
    begin
      AdvanceLineAware(Source, Position, Line);
      Continue;
    end;

    if (C = '/') and (Position < Len) and (Source[Position + 1] = '/') then
    begin
      Inc(Position, 2);
      while (Position <= Len) and not IsLineBreak(Source[Position]) do
        Inc(Position);
      Continue;
    end;

    if C = '{' then
    begin
      Inc(Position);
      while Position <= Len do
      begin
        if Source[Position] = '}' then
        begin
          Inc(Position);
          Break;
        end;
        AdvanceLineAware(Source, Position, Line);
      end;
      Continue;
    end;

    if (C = '(') and (Position < Len) and (Source[Position + 1] = '*') then
    begin
      Inc(Position, 2);
      while Position <= Len do
      begin
        if (Source[Position] = '*') and (Position < Len) and
          (Source[Position + 1] = ')') then
        begin
          Inc(Position, 2);
          Break;
        end;
        AdvanceLineAware(Source, Position, Line);
      end;
      Continue;
    end;

    Break;
  end;

  if Position > Len then
    Exit(False);

  Token.Line := Line;
  C := Source[Position];

  if IsIdentifierStart(C) then
  begin
    Start := Position;
    Inc(Position);
    while (Position <= Len) and IsIdentifierChar(Source[Position]) do
      Inc(Position);
    Token.Kind := tkIdentifier;
    Token.Text := Copy(Source, Start, Position - Start);
    Exit(True);
  end;

  if C = '''' then
  begin
    Inc(Position);
    Text := '';
    while Position <= Len do
    begin
      if Source[Position] = '''' then
      begin
        if (Position < Len) and (Source[Position + 1] = '''') then
        begin
          Text := Text + '''';
          Inc(Position, 2);
          Continue;
        end;
        Inc(Position);
        Break;
      end;

      Text := Text + Copy(Source, Position, 1);
      AdvanceLineAware(Source, Position, Line);
    end;

    Token.Kind := tkString;
    Token.Text := Text;
    Exit(True);
  end;

  Token.Kind := tkSymbol;
  Token.Text := Copy(Source, Position, 1);
  Inc(Position);
  Result := True;
end;

function TokenIsIdentifier(const Token: TToken; const Text: string): Boolean;
begin
  Result := (Token.Kind = tkIdentifier) and SameText(Token.Text, Text);
end;

function ExtractUses(const Source: string): TUsesRefArray;
var
  Position: Integer;
  Line: Integer;
  Token: TToken;
  Buffered: Boolean;
  BufferedToken: TToken;
  Section: TDepTreeDependencySection;
  Refs: TList<TUsesRef>;

  function Next(out AToken: TToken): Boolean;
  begin
    if Buffered then
    begin
      AToken := BufferedToken;
      Buffered := False;
      Exit(True);
    end;
    Result := ReadToken(Source, Position, Line, AToken);
  end;

  procedure Unread(const AToken: TToken);
  begin
    BufferedToken := AToken;
    Buffered := True;
  end;

  procedure ParseUsesList;
  var
    UnitToken: TToken;
    LookAhead: TToken;
    PathToken: TToken;
    ExplicitPath: string;
  begin
    while Next(UnitToken) do
    begin
      if (UnitToken.Kind = tkSymbol) and (UnitToken.Text = ';') then
        Break;

      if (UnitToken.Kind = tkSymbol) and (UnitToken.Text = ',') then
        Continue;

      if UnitToken.Kind <> tkIdentifier then
        Continue;

      ExplicitPath := '';
      if Next(LookAhead) then
      begin
        if TokenIsIdentifier(LookAhead, 'in') then
        begin
          if Next(PathToken) and (PathToken.Kind = tkString) then
            ExplicitPath := PathToken.Text;
        end
        else
          Unread(LookAhead);
      end;

      Refs.Add(TUsesRef.Create(UnitToken.Text, ExplicitPath, Section, UnitToken.Line));
    end;
  end;

begin
  Position := 1;
  Line := 1;
  Buffered := False;
  Section := dsInterface;
  Refs := TList<TUsesRef>.Create;
  try
    while Next(Token) do
    begin
      if TokenIsIdentifier(Token, 'interface') then
        Section := dsInterface
      else if TokenIsIdentifier(Token, 'implementation') then
        Section := dsImplementation
      else if TokenIsIdentifier(Token, 'uses') then
        ParseUsesList;
    end;

    Result := Refs.ToArray;
  finally
    Refs.Free;
  end;
end;

function ExtractModuleName(const Source, FallbackFileName: string): string;
var
  Position: Integer;
  Line: Integer;
  Token: TToken;
  NameToken: TToken;
begin
  Result := ChangeFileExt(ExtractFileName(FallbackFileName), '');
  Position := 1;
  Line := 1;

  while ReadToken(Source, Position, Line, Token) do
  begin
    if TokenIsIdentifier(Token, 'unit') or TokenIsIdentifier(Token, 'program') or
      TokenIsIdentifier(Token, 'library') or TokenIsIdentifier(Token, 'package') then
    begin
      if ReadToken(Source, Position, Line, NameToken) and
        (NameToken.Kind = tkIdentifier) then
        Result := NameToken.Text;
      Exit;
    end;
  end;
end;

end.
