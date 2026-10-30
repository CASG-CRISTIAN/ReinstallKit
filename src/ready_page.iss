[Code]
{ ---------- Ready page: what is going to happen, before starting ---------- }

var
  ReadyBand: TPanel;
  ReadyInfo: TNewStaticText;

{ A band saying what will happen (written when the page is shown) with the list below }
procedure CreateReadyPage;
begin
  ReadyBand := CreateBand(WizardForm.ReadyPage, WizardForm.ReadyMemo.Left, 0, WizardForm.ReadyMemo.Width, #$E896);
  ReadyInfo := AddBandText(ReadyBand, '');
  WizardForm.ReadyLabel.Visible := False;
  { Same background as the app lists, and no horizontal scroll bar }
  WizardForm.ReadyMemo.Color := clWindow;
  WizardForm.ReadyMemo.ScrollBars := ssVertical;
  WizardForm.ReadyMemo.WordWrap := True;
end;

{ The list (UpdateReadyMemo event): the backup, the options and the apps grouped by section }
function ReadyMemoText(const Space, NewLine: String): String;
var
  I, LastSection: Integer;
  Options: String;
begin
  Result := '';
  if BackupMode = BackupExport then
  begin
    Result := CustomMessage('MemoBackup') + NewLine + Space + Msg('MemoExportTo', [BackupDir]) + NewLine +
      Space + Space + CustomMessage('MemoDrivers') + NewLine;
    if ExportWifiCheck.Checked then
      Result := Result + Space + Space + CustomMessage('MemoWifiExport') + NewLine;
    if ExportAppListCheck.Checked then
      Result := Result + Space + Space + CustomMessage('MemoAppList') + NewLine;
    Exit;
  end;
  if BackupMode = BackupImport then
  begin
    Result := CustomMessage('MemoBackup') + NewLine + Space + Msg('MemoImportFrom', [BackupDir]) + NewLine;
    if ImportDriversCheck.Checked then
      Result := Result + Space + Space + CustomMessage('MemoDrivers') + NewLine;
    if ImportWifiCheck.Checked and (WifiProfileCount > 0) then
      Result := Result + Space + Space + Msg('MemoWifiImport', [IntToStr(WifiProfileCount)]) + NewLine;
    Result := Result + NewLine;
  end;
  Options := ChosenOptionsText(Space, NewLine);
  if OneDriveDropped then
    Options := Options + Space + Space + CustomMessage('MemoOneDriveDropped') + NewLine;
  if Options <> '' then
    Result := Result + CustomMessage('MemoOptions') + NewLine + Options + NewLine;

  if CountSelectedApplications > 0 then
  begin
    Result := Result + Msg('MemoApps', [IntToStr(CountSelectedApplications)]) + NewLine;
    LastSection := -1;
    for I := 0 to AppCount - 1 do
      if AppIsSelected(I) then
      begin
        if AppSection[I] <> LastSection then
        begin
          LastSection := AppSection[I];
          Result := Result + Space + SectionNames[LastSection] + NewLine;
        end;
        Result := Result + Space + Space + AppNames[I] + NewLine;
      end;
  end;
end;

{ The band says in one sentence what is going to happen }
procedure UpdateReadyPage;
var
  Count, Bottom: Integer;
  Text, Action: String;
begin
  { The list ends where it ends now: the window may have been resized since it was created }
  Bottom := WizardForm.ReadyMemo.Top + WizardForm.ReadyMemo.Height;
  Count := CountSelectedApplications;
  Action := CustomMessage('ActionInstall');
  if BackupMode = BackupExport then
  begin
    Action := CustomMessage('ActionExport');
    WizardForm.NextButton.Caption := Action;
    Text := CustomMessage('ReadyExport');
  end
  else if (BackupMode = BackupImport) and (Count = 1) then
    Text := CustomMessage('ReadyImportAndOneApp')
  else if (BackupMode = BackupImport) and (Count > 1) then
    Text := Msg('ReadyImportAndApps', [IntToStr(Count)])
  else if BackupMode = BackupImport then
    Text := CustomMessage('ReadyImportOnly')
  else if Count = 1 then
    Text := CustomMessage('ReadyOneApp')
  else if Count > 1 then
    Text := Msg('ReadyApps', [IntToStr(Count)])
  else
    Text := CustomMessage('ReadyOptionsOnly');
  WizardForm.PageDescriptionLabel.Caption := Msg('ReadyDescription', [Action]);
  SetBandText(ReadyInfo, Text + ' ' + CustomMessage('ReadyLogNote'));
  WizardForm.ReadyMemo.Top := ReadyBand.Top + ReadyBand.Height + ScaleY(12);
  WizardForm.ReadyMemo.Height := Bottom - WizardForm.ReadyMemo.Top;
end;
