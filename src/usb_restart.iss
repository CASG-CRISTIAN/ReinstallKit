[Code]
{ ---------- After saving a backup: restarting towards the USB with the Windows installer ---------- }

const
  FirmwareBios = 1;
  FirmwareUefi = 2;
  DriveRemovable = 2;
  DriveFixed = 3;
  { Enough for Setup to close; Windows closes whatever else is open (shutdown /t implies /f) }
  RestartDelay = 10;

var
  UsbRestartScheduled: Boolean;

function GetFirmwareType(var FirmwareType: Integer): Bool;
  external 'GetFirmwareType@kernel32.dll stdcall';
function GetDriveType(Root: String): Cardinal;
  external 'GetDriveTypeW@kernel32.dll stdcall';

{ UEFI or classic BIOS (Legacy/CSM): only UEFI lets Windows choose what to start next }
function FirmwareKind: Integer;
var
  Kind: Integer;
begin
  Kind := 0;
  GetFirmwareType(Kind);
  Result := Kind;
end;

function SecureBootOn: Boolean;
var
  Value: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM, 'SYSTEM\CurrentControlSet\Control\SecureBoot\State',
    'UEFISecureBootEnabled', Value) and (Value = 1);
end;

{ "Use a device" belongs to the recovery environment (WinRE), which ReAgent.xml says is on or off.
  If the file cannot be read it is taken as on, as in any normal installation. }
function RecoveryOn: Boolean;
var
  Xml: AnsiString;
begin
  Result := True;
  if LoadStringFromFile(ExpandConstant('{sys}\Recovery\ReAgent.xml'), Xml) then
    Result := Pos('<InstallState state="0"', Xml) = 0;
end;

{ The drive ("E:") of a Windows installer that UEFI can start: its boot file in \efi\boot and the image
  in \sources. Neither Windows' own drive nor DVD drives: a mounted ISO looks the same but cannot start. }
function FindInstallerUsb: String;
var
  I: Integer;
  Root: String;
begin
  Result := '';
  for I := Ord('C') to Ord('Z') do
  begin
    Root := Chr(I) + ':\';
    if (CompareText(Chr(I) + ':', ExtractFileDrive(ExpandConstant('{win}'))) <> 0) and
       ((GetDriveType(Root) = DriveRemovable) or (GetDriveType(Root) = DriveFixed)) and
       (FileExists(Root + 'efi\boot\bootx64.efi') or FileExists(Root + 'efi\boot\bootaa64.efi')) and
       (FileExists(Root + 'sources\install.wim') or FileExists(Root + 'sources\install.esd') or
        FileExists(Root + 'sources\install.swm')) then
    begin
      Result := Chr(I) + ':';
      Exit;
    end;
  end;
end;

{ Every restart of this module goes through here. shutdown.exe only schedules it and returns at once, and
  refuses what this PC cannot do (going into the firmware, for instance). }
function ScheduleRestart(const Params: String): Boolean;
var
  Code: Integer;
begin
  AddStatusLine('[RESTART] shutdown.exe ' + Params);
  Result := Exec(ExpandConstant('{sys}\shutdown.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
  if not Result then
  begin
    AddStatusLine('[RESTART] Refused, code ' + IntToStr(Code));
    ShowDialog(DialogError, CustomMessage('UsbRestartFailedTitle'),
      Msg('UsbRestartFailedText', ['shutdown ' + Params, SysErrorMessage(Code), IntToStr(Code)]),
      '', [SetupMessage(msgButtonOK)]);
  end;
end;

{ ---------- The restart dialog (built with the pieces of dialogs.iss) ---------- }

{ One line of what the check found, with its icon and color (Light, Dark): done, warning or information.
  Returns where the next line goes. }
function AddUsbStatus(Band: TPanel; Top: Integer; const Glyph, Light, Dark, Text: String): Integer;
var
  Icon: TNewStaticText;
begin
  Icon := CreateGlyph(Band, Glyph, 11, ScaleX(14), Top + ScaleY(1));
  SetTextColor(Icon, Light, Dark);
  Result := Top + AddDialogText(Band, ScaleX(40), Top, Band.Width - ScaleX(54), Text).Height + ScaleY(6);
end;

{ What the check found comes first, in a band: the USB above all, since without it there is nothing to
  start. Then the ways to restart, the recommended one first and chosen, each with what to do after it.
  The technical part (each command, Secure Boot, how to cancel) waits behind "More details". Advanced
  startup is preferred: its "Use a device" starts the USB with two clicks, and from that same menu the
  firmware can be reached too. Returns the shutdown parameters chosen, or '' to not restart. }
function ShowUsbRestartForm(Uefi, Recovery, FirmwareRefused: Boolean; const Usb: String): String;
var
  Band: TPanel;
  Lbl: TNewStaticText;
  Radios: array of TNewRadioButton;
  Commands, Captions, Hints: TArrayOfString;
  Details, Delay: String;
  W, X, Top, I, N: Integer;
begin
  Delay := ' /t ' + IntToStr(RestartDelay);
  N := 0;
  SetArrayLength(Commands, 2);
  SetArrayLength(Captions, 2);
  SetArrayLength(Hints, 2);
  Details := '';
  if Uefi and Recovery then
  begin
    Commands[N] := '/r /o' + Delay;
    Captions[N] := CustomMessage('UsbOptionDevice');
    Hints[N] := CustomMessage('UsbHintDevice');
    Details := Details + '• ' + Msg('UsbDetailDevice', ['shutdown ' + Commands[N]]) + #13#10#13#10;
    N := N + 1;
  end;
  if Uefi and not FirmwareRefused then
  begin
    Commands[N] := '/r /fw' + Delay;
    Captions[N] := CustomMessage('UsbOptionFirmware');
    Hints[N] := CustomMessage('UsbHintFirmware');
    Details := Details + '• ' + Msg('UsbDetailFirmware', ['shutdown ' + Commands[N]]) + #13#10#13#10;
    N := N + 1;
  end;
  if N = 0 then
  begin
    Commands[N] := '/r' + Delay;
    Captions[N] := CustomMessage('UsbOptionPlain');
    Hints[N] := CustomMessage('UsbHintPlain');
    Details := Details + '• ' + Msg('UsbDetailPlain', ['shutdown ' + Commands[N]]) + #13#10#13#10;
    N := N + 1;
  end;
  if Uefi and SecureBootOn then
    Details := Details + '• ' + CustomMessage('UsbDetailSecureBoot') + #13#10#13#10;
  if Uefi and not Recovery then
    Details := Details + '• ' + CustomMessage('UsbDetailNoRecovery') + #13#10#13#10;
  Details := Details + '• ' + Msg('UsbRestartNote', [IntToStr(RestartDelay)]);

  Result := '';
  CreateDialogForm;
  try
    X := DialogMargin;
    W := DialogWidth;
    Top := AddDialogTitle(DialogQuestion, CustomMessage('UsbRestartTitle'));
    Band := CreateColorPanel(DlgForm, ThemeColor('#EEF4FB', '#1F2B37'));
    Band.SetBounds(X, Top, W, ScaleY(40));
    Top := ScaleY(12);
    if Usb <> '' then
      Top := AddUsbStatus(Band, Top, #$E73E, '#0F7B0F', '#6CCB5F', Msg('UsbFound', [Usb]))
    else
      Top := AddUsbStatus(Band, Top, #$E7BA, '#B35900', '#FFB86C', CustomMessage('UsbNotFound'));
    if Uefi then
      Top := AddUsbStatus(Band, Top, #$E73E, '#0F7B0F', '#6CCB5F', CustomMessage('UsbModeUefi'))
    else
      Top := AddUsbStatus(Band, Top, #$E946, '#005FB8', '#60CDFF', CustomMessage('UsbModeBios'));
    if Uefi and SecureBootOn then
      Top := AddUsbStatus(Band, Top, #$E946, '#005FB8', '#60CDFF', CustomMessage('UsbSecureBoot'));
    if Uefi and not Recovery then
      Top := AddUsbStatus(Band, Top, #$E946, '#005FB8', '#60CDFF', CustomMessage('UsbNoRecovery'));
    Band.Height := Top + ScaleY(6);

    Top := Band.Top + Band.Height + ScaleY(16);
    Lbl := AddDialogText(DlgForm, X, Top, W, CustomMessage('UsbChoose'));
    Lbl.Font.Style := [fsBold];
    Top := Top + Lbl.Height + ScaleY(8);
    SetArrayLength(Radios, N);
    for I := 0 to N - 1 do
    begin
      Radios[I] := TNewRadioButton.Create(DlgForm);
      Radios[I].Parent := DlgForm;
      Radios[I].SetBounds(X, Top, W, ScaleY(20));
      if (I = 0) and (N > 1) then
        Radios[I].Caption := Msg('UsbRecommended', [Captions[I]])
      else
        Radios[I].Caption := Captions[I];
      Radios[I].Checked := I = 0;
      Top := Top + ScaleY(21);
      Lbl := AddDialogText(DlgForm, X + ScaleX(19), Top, W - ScaleX(19), Hints[I]);
      MakeMuted(Lbl);
      Top := Top + Lbl.Height + ScaleY(10);
    end;
    DlgBodyBottom := Top;
    AddDialogDetails(Details);
    AddDialogButtons([CustomMessage('UsbRestartButton'), CustomMessage('UsbOptionNone')]);
    if RunDialogForm = 0 then
      for I := 0 to N - 1 do
        if Radios[I].Checked then
          Result := Commands[I];
  finally
    DlgForm.Free;
    DlgForm := nil;
  end;
end;

{ The PC is checked once; if Windows refuses the firmware (it cannot go there), the dialog comes back
  without that way }
procedure OfferUsbRestart;
var
  Command, Usb: String;
  Uefi, Recovery, FirmwareRefused: Boolean;
begin
  Uefi := FirmwareKind = FirmwareUefi;
  Recovery := RecoveryOn;
  Usb := FindInstallerUsb;
  Log('USB restart check: firmware ' + IntToStr(FirmwareKind) + ', Secure Boot ' + IntToStr(Ord(SecureBootOn)) +
    ', WinRE ' + IntToStr(Ord(Recovery)) + ', installer USB "' + Usb + '"');
  FirmwareRefused := False;
  repeat
    Command := ShowUsbRestartForm(Uefi, Recovery, FirmwareRefused, Usb);
    if Command = '' then
      Exit;
    if ScheduleRestart(Command) then
    begin
      UsbRestartScheduled := True;
      Exit;
    end;
    if Pos('/fw', Command) > 0 then
      FirmwareRefused := True;
  until False;
end;

{ When Next is clicked after saving a backup. If something failed or was not done, the user reads what
  before anything else, and the restart towards the USB is only offered if they still want it: the app
  list, for instance, matters less than the drivers. }
procedure OfferRestartAfterBackup;
var
  T: Integer;
  Problems: String;
begin
  Problems := '';
  for T := 0 to TaskCount - 1 do
    if IsProblem(T) or (TaskKinds[T] = TaskCancelled) then
      Problems := Problems + #13#10 + '• ' + TaskTitles[T] + ': ' + TaskResults[T];
  if Problems <> '' then
  begin
    AddStatusLine('[RESTART] The backup is incomplete: the user is told before any restart.');
    if ShowDialog(DialogError, CustomMessage('BackupIncompleteTitle'),
      CustomMessage('BackupIncompleteText') + Problems + #13#10#13#10 + CustomMessage('BackupIncompleteAction'),
      '', [CustomMessage('BackupIncompleteClose'), CustomMessage('BackupIncompleteContinue')]) <> 1 then
      Exit;
  end;
  OfferUsbRestart;
end;
