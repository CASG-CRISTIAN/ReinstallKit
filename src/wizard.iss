[Code]
{ ---------- Wizard: the Inno Setup event functions, which hand the work to the modules ---------- }

procedure InitializeWizard;
begin
  InitializeApplicationCatalog;
  CreateAppPage;
  CreateBackupPages;
  CreateOptionsPage;
  CreateReadyPage;
  CreateInstallPage;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result :=
    ((PageID = ExportDirPage.ID) and (BackupMode <> BackupExport)) or
    ((PageID = ImportDirPage.ID) and (BackupMode <> BackupImport)) or
    (((PageID = wpSelectComponents) or (PageID = OptionsPage.ID)) and (BackupMode = BackupExport));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if (CurPageID = ExportDirPage.ID) or (CurPageID = ImportDirPage.ID) then
  begin
    Result := ValidateBackupDir;
    if Result and (CurPageID = ImportDirPage.ID) then
      ApplyBackupApps(BackupDir);
  end
  else if CurPageID = wpSelectComponents then
  begin
    if CountSelectedApplications > 0 then
      Result := EnsureWinget;
  end
  else if CurPageID = OptionsPage.ID then
  begin
    DropAppsUndoneByTweaks;
    if (CountSelectedApplications = 0) and not ((BackupMode = BackupImport) and ImportChosen) and
       not AnyOptionChosen then
    begin
      ShowDialog(DialogInfo, CustomMessage('NothingSelectedTitle'), CustomMessage('NothingSelectedText'),
        '', [SetupMessage(msgButtonOK)]);
      Result := False;
    end
    else if UpgradeAllChosen and (CountSelectedApplications = 0) then
      Result := EnsureWinget;
  end
  else if CurPageID = InstallPage.ID then
  begin
    Result := InstallDone;
    if Result and not RestartAsked then
    begin
      RestartAsked := True;
      AskRestart;
    end;
  end;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if InstallStarted and not InstallDone then
  begin
    Cancel := False;
    Confirm := False;
    RequestCancel;
  end
  else
  begin
    { Before installing: ours instead of Inno's, which speaks of "the program" not being installed }
    Confirm := False;
    Cancel := ShowDialog(DialogQuestion, CustomMessage('ExitTitle'), CustomMessage('ExitText'),
      '', [CustomMessage('ExitYes'), CustomMessage('ExitNo')]) = 0;
  end;
end;

function UpdateReadyMemo(
  Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := ReadyMemoText(Space, NewLine);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  FooterLabel.Visible := CurPageID = wpSelectComponents;
  if CurPageID = wpSelectComponents then
    ShowAppPage
  else if CurPageID = wpReady then
    UpdateReadyPage
  else if (CurPageID = InstallPage.ID) and not InstallStarted then
    RunInstallation
  else if (CurPageID = wpFinished) and InstallStarted then
    ShowFinishedPage;
end;

function NeedRestart: Boolean;
begin
  { In silent mode Inno decides (/NORESTART prevents it); in the wizard the user was already asked. }
  if WizardSilent then
    Result := RebootNeeded
  else
    Result := RestartChosen;
end;

procedure DeinitializeSetup;
var
  Code: Integer;
begin
  { In case Setup closes with the timer still running }
  if WizardTimer <> 0 then
    KillTimer(0, WizardTimer);
  if NoticeTimer <> 0 then
    KillTimer(0, NoticeTimer);
  { The notifications' registry keys leave with Setup, also before a restart: it waits for them }
  if ToastsSent then
    RunToastScript(' -Remove', ewWaitUntilTerminated);
  { Inno's own log in %TEMP% goes too (the Desktop report has it all): it stays only if Setup was cut short,
    or when /LOG="file" asked for it. It is still open here, so cmd waits two seconds for it to close. }
  if (ExpandConstant('{log}') <> '') and (ExpandConstant('{param:LOG|}') = '') then
    Exec(ExpandConstant('{cmd}'), '/c ping -n 3 127.0.0.1 >nul & del ' + AddQuotes(ExpandConstant('{log}')), '',
      SW_HIDE, ewNoWait, Code);
end;
