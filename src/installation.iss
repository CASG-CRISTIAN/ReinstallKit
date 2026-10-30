[Code]
{ ---------- Installation: the task queue, the end and the restart question ---------- }

var
  InstallStarted: Boolean;
  InstallDone: Boolean;
  RestartAsked: Boolean;
  RestartChosen: Boolean;

function SomethingFailed: Boolean;
begin
  Result := (FailedCount > 0) or (SkippedCount > 0) or StepFailed;
end;

{ Asked when Next is clicked after finishing (the log has already opened for review). If the answer is
  yes, the finished page closes by itself and Setup restarts the PC. After saving a backup the restart
  that makes sense goes towards the Windows installer USB (usb_restart.iss). }
procedure AskRestart;
var
  Text: String;
begin
  if WizardSilent then
    Exit;
  if BackupMode = BackupExport then
  begin
    OfferRestartAfterBackup;
    Exit;
  end;
  { The result in a line and where the log is; the counts per app wait behind "More details" }
  Text := InstallStatusLabel.Caption + #13#10#13#10 + CustomMessage('RestartLogNote');
  { The first button is the default one (Enter): restart only when it is needed }
  if RebootNeeded then
    RestartChosen := ShowDialog(DialogQuestion, CustomMessage('RestartNeededTitle'), Text,
      Trim(SummaryText('')), [CustomMessage('RestartNow'), CustomMessage('RestartLater')]) = 0
  else
    RestartChosen := ShowDialog(DialogQuestion, CustomMessage('RestartQuestion'), Text,
      Trim(SummaryText('')), [CustomMessage('RestartLater'), CustomMessage('RestartNow')]) = 1;
end;

procedure FinishInstallation;
var
  T: Integer;
  Problems: String;
begin
  InstallDone := True;
  KillTimer(0, WizardTimer);
  WizardTimer := 0;
  RestoreStorePinning;
  for T := 0 to TaskCount - 1 do
    if TaskKinds[T] = TaskPending then
    begin
      TaskKinds[T] := TaskCancelled;
      TaskStates[T] := KindText(TaskCancelled);
      if CancelReason <> '' then
        TaskResults[T] := Msg('NotProcessedWhy', [CancelReason])
      else
        TaskResults[T] := CustomMessage('NotProcessed');
    end
    else if TaskRetryAtEnd[T] then
    begin
      { Cancelled before its second try: it stays failed }
      TaskRetryAtEnd[T] := False;
      TaskStates[T] := KindText(TaskKinds[T]);
    end;
  RefreshTaskList;

  if not CancelRequested then
    InstallProgressBar.Position := InstallProgressBar.Max;
  if SomethingFailed then
    InstallProgressBar.State := npbsError;

  { Segoe MDL2 Assets icons: cancel, warning and completed }
  if CancelRequested then
  begin
    InstallStatusLabel.Caption := CustomMessage('StatusCancelled');
    StatusIcon.Caption := #$E711;
  end
  else if SomethingFailed then
  begin
    InstallStatusLabel.Caption := CustomMessage('StatusWarnings');
    StatusIcon.Caption := #$E7BA;
  end
  else
  begin
    InstallStatusLabel.Caption := CustomMessage('StatusOk');
    StatusIcon.Caption := #$E930;
  end;
  SkipButton.Visible := False;
  if DevicesChecked then
  begin
    DevicesButton.Visible := True;
    InstallStatusLabel.Width := DevicesButton.Left - InstallStatusLabel.Left - ScaleX(12);
    InstallDetailLabel.Width := InstallStatusLabel.Width;
  end;
  WizardForm.PageNameLabel.Caption := CustomMessage('FinishedTitle');
  WizardForm.PageDescriptionLabel.Caption := CustomMessage('FinishedDescription');

  if QueueCount > 0 then
    InstallDetailLabel.Caption := Msg('FinalCounts', [IntToStr(InstalledCount), IntToStr(AlreadyInstalledCount),
      IntToStr(FailedCount + SkippedCount)])
  else
    InstallDetailLabel.Caption := '';

  AddStatusLine('[FINISHED] ' + InstallStatusLabel.Caption);
  WriteReport;
  { The end, in the Notification Center too: a click opens the log. It names what failed (the ones that got
    their own notification), since Windows may stack those under it. It waits, so Setup cannot close (and
    remove the keys) before it has written them. }
  Problems := '';
  for T := 0 to TaskCount - 1 do
    if IsProblem(T) and (TaskReasons[T] <> CustomMessage('SkippedByUser')) then
      Problems := Problems + ', ' + TaskTitles[T];
  if Problems <> '' then
    Problems := Msg('ToastProblems', [Copy(Problems, 3, MaxInt)]) + '  ';
  WindowsNotice(InstallStatusLabel.Caption, Trim(Problems + InstallDetailLabel.Caption + '  ' +
    CustomMessage('ToastOpenLog')), LogPath, ewWaitUntilTerminated);

  WizardForm.NextButton.Enabled := True;
  WizardForm.CancelButton.Enabled := False;
  if not WizardSilent then
    OpenLog;
end;

{ Apps that already have a result, for "Installing 12 of 47" }
function AppsFinished(FirstAppTask: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to QueueCount - 1 do
    if (TaskKinds[FirstAppTask + I] <> TaskPending) and (TaskKinds[FirstAppTask + I] <> TaskRunning) then
      Result := Result + 1;
end;

{ Order: restore point first, as the way back; then the backup (the network driver and the Wi-Fi
  networks may be what brings the Internet); then the Windows settings, the apps and the updates. The
  apps: those that can, several at a time (parallel.iss); then, one by one, the rest and whatever the
  pool did not get to; and last, a second try for the failures that may have been passing. }
procedure RunInstallation;
var
  I, T, FirstAppTask, RestoreTask, DriverTask, WifiTask, AppListTask, TweaksTask, FoldersTask, UpgradeTask: Integer;
  Parallel: Integer;
  NeedsInternet: Boolean;
begin
  InstallStarted := True;
  WizardTimer := SetTimer(0, 0, 200, CreateCallback(@WizardTick));
  StepLines := TStringList.Create;
  BuildInstallQueue;

  { Without apps or updates there is nothing to skip }
  SkipButton.Visible := (QueueCount > 0) or ((BackupMode <> BackupExport) and UpgradeAllChosen);
  if not SkipButton.Visible then
  begin
    InstallStatusLabel.Width := StatusBand.Width - InstallStatusLabel.Left - ScaleX(12);
    InstallDetailLabel.Width := InstallStatusLabel.Width;
    if BackupMode = BackupExport then
      WizardForm.PageNameLabel.Caption := CustomMessage('ExportingTitle')
    else if BackupMode = BackupImport then
      WizardForm.PageNameLabel.Caption := CustomMessage('ImportingTitle')
    else
      WizardForm.PageNameLabel.Caption := CustomMessage('ApplyingTitle');
    WizardForm.PageDescriptionLabel.Caption := CustomMessage('StepsOnlyDescription');
    InstallHintLabel.Caption := CustomMessage('StepsOnlyHint');
  end;
  Parallel := ParallelCount;
  if (Parallel > 1) and (QueueCount > 1) then
    WizardForm.PageDescriptionLabel.Caption := Msg('InstallDescriptionParallel', [IntToStr(Parallel)]);

  StartTick := GetTickCount;
  StartedAt := GetDateTimeString(CustomMessage('ReportDateFormat'), '/', ':');
  LogPath := ExpandConstant('{userdesktop}\') + CustomMessage('LogFileName') + ' ' +
    GetDateTimeString('yyyy-mm-dd hh-nn-ss', '-', '-') + '.txt';

  TaskCount := 0;
  CurrentTask := -1;
  RestoreTask := -1;
  DriverTask := -1;
  WifiTask := -1;
  AppListTask := -1;
  TweaksTask := -1;
  FoldersTask := -1;
  UpgradeTask := -1;
  if BackupMode = BackupExport then
  begin
    DriverTask := AddTask(CustomMessage('TaskExportDrivers'), Msg('TaskFolder', [BackupDir]));
    if ExportWifiCheck.Checked then
      WifiTask := AddTask(CustomMessage('TaskExportWifi'), Msg('TaskFolder', [BackupFile(WifiFolder)]));
    if ExportAppListCheck.Checked then
      AppListTask := AddTask(CustomMessage('TaskExportAppList'), Msg('TaskFile', [BackupFile(AppListFile)]));
  end
  else
  begin
    if RestorePointChosen then
      RestoreTask := AddTask(CustomMessage('TaskRestorePoint'), CustomMessage('RestorePointDetail'));
    if BackupMode = BackupImport then
    begin
      if ImportDriversCheck.Checked then
        DriverTask := AddTask(CustomMessage('TaskImportDrivers'), Msg('TaskFolder', [BackupDir]));
      if ImportWifiCheck.Checked and (WifiProfileCount > 0) then
        WifiTask := AddTask(CustomMessage('TaskImportWifi'), Msg('TaskFolder', [BackupFile(WifiFolder)]));
    end;
    if ChosenTweakCount > 0 then
      TweaksTask := AddTask(CustomMessage('TaskTweaks'), CustomMessage('TweaksDetail'));
    if FoldersChosen then
      FoldersTask := AddTask(CustomMessage('TaskFolders'), Msg('FoldersDetail', [FoldersDrive]));
  end;
  FirstAppTask := TaskCount;
  for I := 0 to QueueCount - 1 do
    AddTask(AppNames[InstallQueue[I]], Msg('TaskPackage', [AppPackageIDs[InstallQueue[I]]]));
  if (BackupMode <> BackupExport) and UpgradeAllChosen then
    UpgradeTask := AddTask(CustomMessage('TaskUpgradeAll'), CustomMessage('UpgradeAllDetail'));
  RefreshTaskList;

  InstallProgressBar.Min := 0;
  InstallProgressBar.Max := TaskCount;
  InstallProgressBar.Position := 0;

  WizardForm.BackButton.Enabled := False;
  WizardForm.NextButton.Enabled := False;

  if (RestoreTask >= 0) and not CancelRequested then
  begin
    RunRestorePointStep(RestoreTask);
    StepDone;
  end;
  if (DriverTask >= 0) and not CancelRequested then
  begin
    RunDriverStep(DriverTask);
    StepDone;
  end;
  if (WifiTask >= 0) and not CancelRequested then
  begin
    if BackupMode = BackupExport then
      RunWifiExportStep(WifiTask)
    else
      RunWifiImportStep(WifiTask);
    StepDone;
  end;
  if (AppListTask >= 0) and not CancelRequested then
  begin
    RunAppListExportStep(AppListTask);
    StepDone;
  end;
  if (TweaksTask >= 0) and not CancelRequested then
  begin
    RunTweaksStep(TweaksTask);
    StepDone;
  end;
  if (FoldersTask >= 0) and not CancelRequested then
  begin
    RunFoldersStep(FoldersTask);
    StepDone;
  end;

  NeedsInternet := (QueueCount > 0) or (UpgradeTask >= 0);
  if NeedsInternet and not CancelRequested then
  begin
    if (WifiTask >= 0) and (BackupMode = BackupImport) then
      WaitForInternet(20);
    StatusBase := CustomMessage('CheckingInternet');
    InstallStatusLabel.Caption := StatusBase;
    if not ConfirmInternet then
    begin
      CancelRequested := True;
      CancelReason := CustomMessage('NoInternetReason');
      AddStatusLine('[CANCELLED] No Internet connection: the apps are not installed.');
    end;
    if Parallel > 1 then
      AddStatusLine('[START] Requested apps: ' + IntToStr(QueueCount) + '. Up to ' + IntToStr(Parallel) +
        ' at a time; Microsoft Store apps and those installed as the user, one by one.')
    else
      AddStatusLine('[START] Requested apps: ' + IntToStr(QueueCount) +
        '. They are installed one by one to avoid conflicts.');
  end;
  if (Parallel > 1) and not CancelRequested then
    RunPool(FirstAppTask, Parallel);
  for I := 0 to QueueCount - 1 do
  begin
    if CancelRequested then
      Break;
    if TaskKinds[FirstAppTask + I] <> TaskPending then
      Continue;
    StatusBase := Msg('InstallingCount', [IntToStr(AppsFinished(FirstAppTask) + 1), IntToStr(QueueCount),
      AppNames[InstallQueue[I]]]);
    InstallStatusLabel.Caption := StatusBase;
    InstallApp(FirstAppTask + I, InstallQueue[I]);
    StepDone;
  end;
  { The failures that may have come from something another installer had in use, once more }
  RetryingAtEnd := True;
  for I := 0 to QueueCount - 1 do
  begin
    T := FirstAppTask + I;
    if CancelRequested then
      Break;
    if not TaskRetryAtEnd[T] then
      Continue;
    TaskRetryAtEnd[T] := False;
    FailedCount := FailedCount - 1;
    StatusBase := Msg('RetryingApp', [AppNames[InstallQueue[I]]]);
    InstallStatusLabel.Caption := StatusBase;
    AddTaskDetail(T, CustomMessage('RetryingLine'));
    AddStatusLine('[RETRY] ' + AppNames[InstallQueue[I]] + ': second try after the other apps.');
    InstallApp(T, InstallQueue[I]);
  end;
  if (UpgradeTask >= 0) and not CancelRequested then
  begin
    RunUpgradeAllStep(UpgradeTask);
    StepDone;
  end;

  FinishInstallation;
end;

{ Cancel during the installation: the queue stops. An app or the update being installed is cut at once,
  as Skip does (the report says it may be left half done); a step of the backup or the Windows settings
  is not cut, so as not to leave Windows half changed, and the queue stops when it ends. }
procedure RequestCancel;
begin
  if CancelRequested then
    Exit;
  CancelRequested := True;
  WizardForm.CancelButton.Enabled := False;
  StatusBase := CustomMessage('Cancelling');
  InstallStatusLabel.Caption := StatusBase;
  AddStatusLine('[CANCELLING] Stopping now; an app being installed is cut.');
  if PoolActive then
    PoolCancel
  else if SkipButton.Visible and SkipButton.Enabled then
    SkipCurrentApp(CustomMessage('CutByCancel'));
end;

{ Finished page: a heading that depends on how it ended, the summary and where the log is }
procedure ShowFinishedPage;
var
  Delta: Integer;
begin
  if CancelRequested then
    WizardForm.FinishedHeadingLabel.Caption := CustomMessage('FinishedHeadingCancelled')
  else if SomethingFailed then
    WizardForm.FinishedHeadingLabel.Caption := CustomMessage('FinishedHeadingWarnings')
  else if BackupMode = BackupExport then
    WizardForm.FinishedHeadingLabel.Caption := CustomMessage('FinishedHeadingBackup')
  else
    WizardForm.FinishedHeadingLabel.Caption := CustomMessage('FinishedHeadingOk');
  WizardForm.FinishedLabel.Caption := InstallStatusLabel.Caption + #13#10#13#10 + SummaryText('') + #13#10 +
    CustomMessage('LogSavedAt') + #13#10 + ExtractFileName(LogPath);
  { The label does not grow by itself and the restart buttons sit below it. }
  Delta := WizardForm.AdjustLabelHeight(WizardForm.FinishedLabel);
  WizardForm.YesRadio.Top := WizardForm.YesRadio.Top + Delta;
  WizardForm.NoRadio.Top := WizardForm.NoRadio.Top + Delta;
  if RestartChosen then
  begin
    { The user already said yes: it closes by itself and Setup restarts the PC. }
    WizardForm.YesRadio.Checked := True;
    PostMessage(WizardForm.NextButton.Handle, BM_CLICK, 0, 0);
  end
  else if UsbRestartScheduled then
    { shutdown.exe restarts the PC in a few seconds: Setup gets out of the way }
    PostMessage(WizardForm.NextButton.Handle, BM_CLICK, 0, 0);
end;
