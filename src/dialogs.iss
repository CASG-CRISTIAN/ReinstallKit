[Code]
{ ---------- The installer's dialogs: one window for all of them ----------
  Wider than Windows' task dialog, whose size cannot be changed: texts and long buttons no longer squeeze
  into a narrow column, and in dark mode its title got cut. The title goes in the accent color beside an
  icon of its kind, buttons are of normal size (stacked only when they do not fit in a row), and when
  there is much to read the explanation waits behind "More details". }

const
  DialogError = 0;
  DialogWarning = 1;
  DialogQuestion = 2;
  DialogInfo = 3;
  { Button I closes the dialog with this plus I }
  DialogFirstResult = 1000;

var
  DlgForm: TSetupForm;
  DlgBodyBottom: Integer;          { where the details link, or the buttons, go }
  DlgMoreLink: TNewLinkLabel;      { nil when there are no details }
  DlgDetails: TNewStaticText;
  DlgButtons: array of TNewButton;
  DlgStacked: Boolean;             { buttons one under the other: they did not fit in a row }

function DialogMargin: Integer;
begin
  Result := ScaleX(20);
end;

function DialogWidth: Integer;
begin
  Result := DlgForm.ClientWidth - 2 * DialogMargin;
end;

{ A wrapped text of the dialog at Top; its height fits the text }
function AddDialogText(Parent: TWinControl; Left, Top, Width: Integer; const Text: String): TNewStaticText;
begin
  Result := TNewStaticText.Create(DlgForm);
  Result.Parent := Parent;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.SetBounds(Left, Top, Width, ScaleY(16));
  Result.Caption := Text;
  Result.AdjustHeight;
end;

procedure CreateDialogForm;
begin
  DlgForm := CreateCustomForm(ScaleX(480), ScaleY(300), False, False);
  { The size asked for above gets scaled once more: the width goes by the wizard's }
  DlgForm.ClientWidth := WizardForm.ClientWidth * 7 div 10;
  DlgForm.Caption := WizardForm.Caption;
  DlgMoreLink := nil;
  DlgDetails := nil;
  SetArrayLength(DlgButtons, 0);
end;

{ The title beside the icon of its kind (Segoe MDL2 Assets); returns where the content goes }
function AddDialogTitle(Kind: Integer; const Title: String): Integer;
var
  Icon, Lbl: TNewStaticText;
begin
  case Kind of
    DialogError:
      begin
        Icon := CreateGlyph(DlgForm, #$EA39, 16, DialogMargin, ScaleY(18));
        SetTextColor(Icon, '#C42B1C', '#FF99A4');
      end;
    DialogWarning:
      begin
        Icon := CreateGlyph(DlgForm, #$E7BA, 16, DialogMargin, ScaleY(18));
        SetTextColor(Icon, '#B35900', '#FFB86C');
      end;
    DialogQuestion:
      Icon := CreateGlyph(DlgForm, #$E9CE, 16, DialogMargin, ScaleY(18));
  else
    Icon := CreateGlyph(DlgForm, #$E946, 16, DialogMargin, ScaleY(18));
  end;
  Lbl := AddDialogText(DlgForm, DialogMargin + ScaleX(34), ScaleY(18), DialogWidth - ScaleX(34), Title);
  Lbl.Font.Size := 12;
  Lbl.AdjustHeight;
  MakeAccent(Lbl);
  Result := Lbl.Top + Lbl.Height + ScaleY(12);
end;

{ The details and then the buttons, under the body; the window fits them }
procedure LayoutDialog;
var
  Top, I: Integer;
begin
  Top := DlgBodyBottom;
  if DlgMoreLink <> nil then
  begin
    DlgMoreLink.Top := Top + ScaleY(2);
    Top := DlgMoreLink.Top + DlgMoreLink.Height + ScaleY(10);
    if DlgDetails.Visible then
    begin
      DlgDetails.Top := Top;
      Top := Top + DlgDetails.Height + ScaleY(10);
    end;
  end;
  Top := Top + ScaleY(8);
  for I := 0 to GetArrayLength(DlgButtons) - 1 do
  begin
    DlgButtons[I].Top := Top;
    if DlgStacked and (I < GetArrayLength(DlgButtons) - 1) then
      Top := Top + DlgButtons[I].Height + ScaleY(8);
  end;
  DlgForm.ClientHeight := Top + ScaleY(28) + ScaleY(16);
end;

procedure DialogMoreClick(Sender: TObject; const Link: String; LinkType: TSysLinkType);
begin
  DlgDetails.Visible := not DlgDetails.Visible;
  if DlgDetails.Visible then
    DlgMoreLink.Caption := '<a>' + CustomMessage('LessDetails') + '</a>'
  else
    DlgMoreLink.Caption := '<a>' + CustomMessage('MoreDetails') + '</a>';
  LayoutDialog;
end;

{ "More details" under the body, and the details themselves, hidden at first }
procedure AddDialogDetails(const Details: String);
begin
  DlgMoreLink := TNewLinkLabel.Create(DlgForm);
  DlgMoreLink.Parent := DlgForm;
  DlgMoreLink.UseVisualStyle := True;
  DlgMoreLink.Left := DialogMargin;
  DlgMoreLink.Caption := '<a>' + CustomMessage('MoreDetails') + '</a>';
  DlgMoreLink.OnLinkClick := @DialogMoreClick;
  DlgDetails := AddDialogText(DlgForm, DialogMargin, 0, DialogWidth, Details);
  MakeMuted(DlgDetails);
  DlgDetails.Visible := False;
end;

{ The buttons, in a row on the right; the first one is the default (Enter) and the last one what closing
  the dialog means (Esc) }
procedure AddDialogButtons(const Captions: array of String);
var
  I, N, Total, Left: Integer;
  Widths: array of Integer;
begin
  N := GetArrayLength(Captions);
  SetArrayLength(DlgButtons, N);
  SetArrayLength(Widths, N);
  Total := 0;
  for I := 0 to N - 1 do
  begin
    DlgButtons[I] := TNewButton.Create(DlgForm);
    DlgButtons[I].Parent := DlgForm;
    DlgButtons[I].Caption := Captions[I];
    DlgButtons[I].ModalResult := DialogFirstResult + I;
    Widths[I] := DlgForm.CalculateButtonWidth([Captions[I]]);
    Total := Total + Widths[I] + ScaleX(8);
  end;
  DlgButtons[0].Default := True;
  DlgButtons[N - 1].Cancel := True;
  DlgStacked := Total - ScaleX(8) > DialogWidth;
  Left := DlgForm.ClientWidth - DialogMargin - Total + ScaleX(8);
  for I := 0 to N - 1 do
    if DlgStacked then
      DlgButtons[I].SetBounds(DialogMargin, 0, DialogWidth, ScaleY(28))
    else
    begin
      DlgButtons[I].SetBounds(Left, 0, Widths[I], ScaleY(28));
      Left := Left + Widths[I] + ScaleX(8);
    end;
  LayoutDialog;
end;

{ Shows the dialog built so far; returns the index of the button clicked, closing it counts as the last }
function RunDialogForm: Integer;
var
  Modal: Integer;
begin
  DlgForm.ActiveControl := DlgButtons[0];
  DlgForm.FlipAndCenterIfNeeded(True, WizardForm, False);
  Modal := DlgForm.ShowModal;
  if Modal >= DialogFirstResult then
    Result := Modal - DialogFirstResult
  else
    Result := GetArrayLength(DlgButtons) - 1;
end;

{ The usual dialog: icon and title, the text, the details when there are any, and the buttons. Returns
  the index of the button clicked. }
function ShowDialog(Kind: Integer; const Title, Text, Details: String; const Buttons: array of String): Integer;
var
  Top: Integer;
begin
  CreateDialogForm;
  try
    Top := AddDialogTitle(Kind, Title);
    if Text <> '' then
      Top := Top + AddDialogText(DlgForm, DialogMargin, Top, DialogWidth, Text).Height + ScaleY(12);
    DlgBodyBottom := Top;
    if Details <> '' then
      AddDialogDetails(Details);
    AddDialogButtons(Buttons);
    Result := RunDialogForm;
  finally
    DlgForm.Free;
    DlgForm := nil;
  end;
end;
