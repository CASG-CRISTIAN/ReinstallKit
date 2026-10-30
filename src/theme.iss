[Code]
{ ---------- Theme: colors, icons and bands shared by every page ---------- }

{ Windows 11 colors. With WizardStyle=modern dynamic the wizard follows the Windows mode. }
function ThemeColor(const Light, Dark: String): TColor;
begin
  if IsDarkInstallMode then
    Result := StrToColor(Dark)
  else
    Result := StrToColor(Light);
end;

{ In dark mode Inno's style paints text in its own color; to use ours the font must be taken from it. }
procedure SetTextColor(Lbl: TNewStaticText; const Light, Dark: String);
begin
  Lbl.StyleElements := Lbl.StyleElements - [seFont];
  Lbl.Font.Color := ThemeColor(Light, Dark);
end;

procedure MakeAccent(Lbl: TNewStaticText);
begin
  SetTextColor(Lbl, '#005FB8', '#60CDFF');
end;

procedure MakeMuted(Lbl: TNewStaticText);
begin
  SetTextColor(Lbl, '#5C5C5C', '#C8C8C8');
end;

{ Icon from the Segoe MDL2 Assets font (ships with Windows 10 and 11), in the accent color }
function CreateGlyph(Parent: TWinControl; const Glyph: String; Size, Left, Top: Integer): TNewStaticText;
begin
  Result := TNewStaticText.Create(WizardForm);
  Result.Parent := Parent;
  Result.Font.Name := 'Segoe MDL2 Assets';
  Result.Font.Size := Size;
  Result.Caption := Glyph;
  Result.Left := Left;
  Result.Top := Top;
  MakeAccent(Result);
end;

{ Flat panel in a color of our own; Inno's dark style would paint its own over it }
function CreateColorPanel(Parent: TWinControl; Color: TColor): TPanel;
begin
  Result := TPanel.Create(WizardForm);
  Result.Parent := Parent;
  Result.BevelOuter := bvNone;
  Result.ParentBackground := False;
  Result.StyleElements := Result.StyleElements - [seClient];
  Result.Color := Color;
end;

{ Soft-colored band with an icon on the left: the shared building block of every page. The wizard can be
  resized (WizardResizable, on by default with the modern style): bands grow with it, like the controls
  of each page, which say how with their Anchors. }
function CreateBand(Parent: TWinControl; Left, Top, Width: Integer; const Glyph: String): TPanel;
begin
  Result := CreateColorPanel(Parent, ThemeColor('#EEF4FB', '#1F2B37'));
  Result.SetBounds(Left, Top, Width, ScaleY(44));
  Result.Anchors := [akLeft, akTop, akRight];
  if Glyph <> '' then
    CreateGlyph(Result, Glyph, 15, ScaleX(13), ScaleY(11));
end;

{ Changes a band's text; the band grows until it fits }
procedure SetBandText(Lbl: TNewStaticText; const Text: String);
begin
  Lbl.Caption := Text;
  Lbl.AdjustHeight;
  Lbl.Parent.Height := Lbl.Top + Lbl.Height + ScaleY(12);
end;

function AddBandText(Band: TPanel; const Text: String): TNewStaticText;
begin
  Result := TNewStaticText.Create(WizardForm);
  Result.Parent := Band;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.SetBounds(ScaleX(46), ScaleY(12), Band.Width - ScaleX(58), ScaleY(16));
  Result.Anchors := [akLeft, akTop, akRight];
  SetBandText(Result, Text);
end;

{ Folder pages put their explanation in a band and their controls move below it }
procedure AddDirBand(Page: TInputDirWizardPage; const Glyph, Text: String);
var
  Band: TPanel;
  Delta: Integer;
begin
  Band := CreateBand(Page.Surface, 0, 0, Page.SurfaceWidth, Glyph);
  AddBandText(Band, Text);
  Page.SubCaptionLabel.Visible := False;
  Delta := Band.Height + ScaleY(16) - Page.PromptLabels[0].Top;
  Page.PromptLabels[0].Top := Page.PromptLabels[0].Top + Delta;
  Page.Edits[0].Top := Page.Edits[0].Top + Delta;
  Page.Buttons[0].Top := Page.Buttons[0].Top + Delta;
end;
