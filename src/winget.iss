[Code]
{ ---------- WinGet: preliminary checks and the installation of each app ---------- }

const
  BusyRetrySeconds = 30;
  { The Internet is up if WinGet's CDN or Windows' own connectivity check answers (HEAD requests:
    nothing is downloaded). Two of them, in case a filter blocks one. }
  InternetCheckUrl = 'https://cdn.winget.microsoft.com/cache/source.msix';
  WindowsCheckUrl = 'http://www.msftconnecttest.com/connecttest.txt';

  { WinGet exit codes: HRESULT 0x8A15xxxx read as a signed integer.
    "winget error <code>" explains any of them. }
  WingetUpdateNotApplicable = -1978335189;      { 0x8A15002B }
  WingetUpgradeVersionNotNewer = -1978335153;   { 0x8A15004F }
  WingetUpgradeVersionUnknown = -1978335152;    { 0x8A150050 }
  WingetPackageAlreadyInstalled = -1978335135;  { 0x8A150061 }
  WingetPackageIsPinned = -1978335128;          { 0x8A150068 }
  WingetTechnologyMismatch = -1978335090;       { 0x8A15008E }
  WingetInstallAlreadyInstalled = -1978334963;  { 0x8A15010D }
  WingetInstallDowngrade = -1978334962;         { 0x8A15010E }
  WingetUpgradeNotSupported = -1978334956;      { 0x8A150114 }
  WingetPackageInUse = -1978334975;             { 0x8A150101 }
  WingetFileInUse = -1978334973;                { 0x8A150103 }
  WingetInUseByApplication = -1978334959;       { 0x8A150111 }
  WingetRebootRequired = -1978334967;           { 0x8A150109 }
  WingetRebootInitiated = -1978334965;          { 0x8A15010B }
  WingetRebootRequiredToInstall = -1978334966;  { 0x8A15010A }
  WingetInstallInProgress = -1978334974;        { 0x8A150102 }
  WingetProhibitsElevation = -1978335146;       { 0x8A150056 }
  WingetNoApplicableInstaller = -1978335216;    { 0x8A150010 }
  WingetNoApplicationsFound = -1978335212;      { 0x8A150014 }
  WingetMultipleApplicationsFound = -1978335210; { 0x8A150016 }
  WingetNoManifestFound = -1978335209;          { 0x8A150017 }
  WingetInstallerFailed = -1978335226;          { 0x8A150006: the installer ended with an error of its own }
  WingetDownloadFailed = -1978335224;           { 0x8A150008 }
  WingetHashMismatch = -1978335215;             { 0x8A150011 }
  WingetNoNetwork = -1978334969;                { 0x8A150107 }
  WingetDiskFull = -1978334971;                 { 0x8A150105 }
  WingetMissingDependency = -1978334972;        { 0x8A150104 }
  WingetDependenciesFailed = -1978334960;       { 0x8A150110 }
  WingetCancelledByUser = -1978334964;          { 0x8A15010C }
  WingetBlockedByPolicy = -1978334961;          { 0x8A15010F }
  WingetSystemNotSupported = -1978334957;       { 0x8A150113 }
  WingetPinnedCertMismatch = -1978335138;       { 0x8A15005E: Microsoft Store's certificate is not an expected one }
  WingetSourceCacheMissing = -2147020496;       { 0x80071130: "Failed to open the predefined source" }

var
  InstalledCount: Integer;
  AlreadyInstalledCount: Integer;
  FailedCount: Integer;
  SkippedCount: Integer;
  AppInstallerUpdateTried: Boolean;
  StorePinningAsked: Boolean;   { asked once per run }
  StorePinningOff: Boolean;     { turned off by us: RestoreStorePinning turns it back on }
  RetryingAtEnd: Boolean;       { the second try of the failed apps, after the rest: no third one }

function WingetWorks: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec('winget.exe', '--version', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and
    (ResultCode = 0);
end;

function EnsureWinget: Boolean;
var
  ResultCode: Integer;
begin
  Result := WingetWorks;
  if Result then
    Exit;

  { After the first sign-in Windows registers "App Installer" in the background. If it has not done
    so yet, this is the command Microsoft documents to force it. }
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -Command "Add-AppxPackage -RegisterByFamilyName ' +
    '-MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := WingetWorks;

  if not Result then
    ShowDialog(DialogError, CustomMessage('NoWingetTitle'), CustomMessage('NoWingetText'),
      '', [SetupMessage(msgButtonOK)]);
end;

function UrlResponds(const Url: String): Boolean;
begin
  try
    Result := DownloadTemporaryFileSize(Url) > 0;
  except
    Result := False;
  end;
end;

function InternetAvailable: Boolean;
begin
  Result := UrlResponds(InternetCheckUrl) or UrlResponds(WindowsCheckUrl);
end;

{ After restoring the Wi-Fi networks Windows needs a few seconds to connect by itself }
procedure WaitForInternet(Seconds: Integer);
var
  Start: DWORD;
begin
  StatusBase := CustomMessage('WaitingForWifi');
  InstallStatusLabel.Caption := StatusBase;
  Start := GetTickCount;
  while not InternetAvailable and (GetTickCount - Start < Seconds * 1000) do
    WaitSeconds(2);
end;

{ Before installing apps. They are all downloaded from the Internet, so without a connection the only
  options are retrying or cancelling them; returns False if they are cancelled (straight away in
  silent mode). }
function ConfirmInternet: Boolean;
begin
  Result := True;
  while not InternetAvailable do
  begin
    AddStatusLine('[NO INTERNET] No Internet connection.');
    Result := False;
    if WizardSilent then
      Exit;
    ModalOpen := True;
    Result := ShowDialog(DialogError, CustomMessage('NoInternetTitle'),
      CustomMessage('NoInternetText') + #13#10#13#10 + CustomMessage('NoInternetAction'),
      '', [CustomMessage('Retry'), CustomMessage('CancelInstall')]) = 0;
    ModalOpen := False;
    if not Result then
      Exit;
  end;
end;

{ Turns a WinGet exit code into how the task ended (TaskInstalled, TaskAlready or TaskFailed) and a
  short reason, which is what the summary groups by. Hint is the advice for the report. }
function ClassifyWinget(Code: Integer; var Reason, Hint: String): Integer;
begin
  Result := TaskFailed;
  Hint := '';
  case Code of
    0:
      begin
        Result := TaskInstalled;
        Reason := CustomMessage('WgInstalled');
      end;
    WingetRebootRequired, WingetRebootInitiated:
      begin
        Result := TaskInstalled;
        Reason := CustomMessage('WgInstalledReboot');
      end;
    WingetUpdateNotApplicable, WingetUpgradeVersionNotNewer, WingetPackageAlreadyInstalled:
      begin
        Result := TaskAlready;
        Reason := CustomMessage('WgUpToDate');
      end;
    WingetInstallAlreadyInstalled, WingetInstallDowngrade:
      begin
        Result := TaskAlready;
        Reason := CustomMessage('WgOtherVersion');
      end;
    WingetUpgradeVersionUnknown, WingetTechnologyMismatch, WingetUpgradeNotSupported, WingetPackageIsPinned:
      begin
        Result := TaskAlready;
        Reason := CustomMessage('WgCantUpgrade');
      end;
    WingetPackageInUse, WingetFileInUse, WingetInUseByApplication:
      begin
        Result := TaskAlready;
        Reason := CustomMessage('WgWasOpen');
        Hint := CustomMessage('WgWasOpenHint');
      end;
    WingetInstallInProgress:
      begin
        Reason := CustomMessage('WgBusy');
        Hint := CustomMessage('WgBusyHint');
      end;
    WingetRebootRequiredToInstall:
      begin
        Reason := CustomMessage('WgRebootFirst');
        Hint := CustomMessage('WgRebootFirstHint');
      end;
    WingetProhibitsElevation:
      begin
        Reason := CustomMessage('WgNoElevation');
        Hint := CustomMessage('WgNoElevationHint');
      end;
    WingetNoApplicationsFound, WingetNoManifestFound, WingetMultipleApplicationsFound:
      begin
        Reason := CustomMessage('WgUnknownId');
        Hint := CustomMessage('WgUnknownIdHint');
      end;
    WingetNoApplicableInstaller, WingetSystemNotSupported:
      Reason := CustomMessage('WgNotApplicable');
    WingetDownloadFailed, WingetNoNetwork:
      begin
        Reason := CustomMessage('WgDownload');
        Hint := CustomMessage('WgDownloadHint');
      end;
    WingetHashMismatch:
      begin
        Reason := CustomMessage('WgHash');
        Hint := CustomMessage('WgHashHint');
      end;
    WingetDiskFull:
      Reason := CustomMessage('WgDiskFull');
    WingetMissingDependency, WingetDependenciesFailed:
      Reason := CustomMessage('WgDependency');
    WingetCancelledByUser:
      Reason := CustomMessage('WgCancelled');
    WingetBlockedByPolicy:
      Reason := CustomMessage('WgPolicy');
    WingetPinnedCertMismatch:
      begin
        Reason := CustomMessage('WgStoreCertificate');
        Hint := CustomMessage('WgStoreCertificateHint');
      end;
    WingetSourceCacheMissing:
      begin
        Reason := CustomMessage('WgSourceNotReady');
        Hint := CustomMessage('WgNotReadyHint');
      end;
  else
    begin
      Reason := Msg('WgInstallerFailed', [CodeText(Code)]);
      Hint := Msg('WgErrorHint', [Format('%.8x', [Code])]);
    end;
  end;
end;

{ With 0x8A150006 WinGet only says that the installer failed. The installer's own exit code, which is
  what its maker documents, ends the last line WinGet wrote ("Installer failed with exit code: 1603", in
  the language of Windows). Small codes (MSI's 1603...) in decimal, the rest in hex; '' if none. }
function InstallerExitCode(T: Integer): String;
var
  L, I, K, D: Integer;
  Line: String;
  N: Int64;
begin
  Result := '';
  for L := TaskDetails[T].Count - 1 downto TaskDetails[T].Count - 3 do
  begin
    if L < 0 then
      Exit;
    Line := TaskDetails[T].Strings[L];
    I := Length(Line);
    while (I > 0) and (Line[I] >= '0') and (Line[I] <= '9') do
      I := I - 1;
    if (I > 0) and (I < Length(Line)) and (Line[I] = ' ') then
    begin
      N := StrToInt64Def(Copy(Line, I + 1, MaxInt), -1);
      if (N > 0) and (N < 65536) then
        Result := IntToStr(N)
      else if (N >= 65536) and (N <= 4294967295) then
      begin
        for K := 1 to 8 do
        begin
          D := N mod 16;
          Result := Copy('0123456789ABCDEF', D + 1, 1) + Result;
          N := N div 16;
        end;
        Result := '0x' + Result;
      end;
      if Result <> '' then
        Exit;
    end;
  end;
end;

{ App language: almost every app uses the Windows one and needs nothing. Mozilla publishes one package
  per language (WingetID_EN/_FR columns of the CSV) and Battle.net gets it here.
  Battle.net is the only case; move this to a CSV column if more show up. }

{ Battle.net requires a folder: without --location WinGet asks for it and, unable to ask, fails }
function LocationArg(const PackageID: String): String;
begin
  Result := '';
  if PackageID = 'Blizzard.BattleNet' then
    Result := ' --location "' + ExpandConstant('{commonpf32}\Battle.net') + '"';
end;

{ Its manifest already passes --lang=enUS: it gets its own arguments with the chosen language }
function LanguageArg(const PackageID: String): String;
begin
  Result := '';
  if PackageID = 'Blizzard.BattleNet' then
    Result := ' --override "--lang=' + CustomMessage('BlizzardLanguage') + ' --installpath=\"' +
      ExpandConstant('{commonpf32}\Battle.net') + '\""';
end;

{ WinGet checks Microsoft Store's certificate against a list that App Installer carries, and a freshly
  installed Windows may come with an App Installer whose list is out of date. Updating it from the winget
  source fixes that case; it is tried once per run. The other cause, an antivirus, proxy or VPN that
  inspects HTTPS, is left to the user (WgStoreCertificateHint). }
function UpdateAppInstaller(T: Integer): Boolean;
var
  Code: Integer;
begin
  Result := False;
  if AppInstallerUpdateTried then
    Exit;
  AppInstallerUpdateTried := True;
  AddTaskDetail(T, CustomMessage('UpdatingAppInstaller'));
  AddStatusLine('[STORE] Certificate check failed (0x8A15005E): updating App Installer once.');
  Result := RunSystemCommand('winget.exe', 'upgrade --id Microsoft.AppInstaller -e --source winget --silent ' +
    '--disable-interactivity --accept-package-agreements --accept-source-agreements', False, Code) and (Code = 0);
end;

{ If WinGet still rejects Microsoft Store's certificate with an updated App Installer, something on the
  way (an antivirus, proxy or VPN that inspects HTTPS) shows its own. WinGet's official admin setting
  BypassCertificatePinningForMicrosoftStore makes it check the Store the way Windows does, which the
  Store app itself already does. Only if the user agrees, and only until the end of this run. }
function AllowStoreWithoutPinning(T: Integer): Boolean;
var
  Code: Integer;
begin
  Result := False;
  if StorePinningAsked or WizardSilent then
    Exit;
  StorePinningAsked := True;
  ModalOpen := True;
  { What is proposed comes first; why WinGet refuses the Store waits behind "More details" }
  Result := ShowDialog(DialogQuestion, CustomMessage('StorePinningTitle'), CustomMessage('StorePinningAction'),
    CustomMessage('StorePinningText'), [CustomMessage('StorePinningYes'), CustomMessage('StorePinningNo')]) = 0;
  ModalOpen := False;
  if not Result then
  begin
    AddStatusLine('[STORE] The user kept the certificate check.');
    Exit;
  end;
  AddTaskDetail(T, CustomMessage('StorePinningOffDetail'));
  Result := RunSystemCommand('winget.exe', 'settings --enable BypassCertificatePinningForMicrosoftStore',
    False, Code) and (Code = 0);
  StorePinningOff := Result;
end;

{ At the end, also after cancelling }
procedure RestoreStorePinning;
var
  Code: Integer;
begin
  if not StorePinningOff then
    Exit;
  StorePinningOff := False;
  { Back to the default, as if never touched; a WinGet without "reset" at least turns it off }
  if not RunSystemCommand('winget.exe', 'settings reset --setting BypassCertificatePinningForMicrosoftStore',
    False, Code) or (Code <> 0) then
    RunSystemCommand('winget.exe', 'settings --disable BypassCertificatePinningForMicrosoftStore', False, Code);
  AddStatusLine('[STORE] Certificate check turned back on (code ' + IntToStr(Code) + ').');
end;

{ Worth another try after a while: another installation in progress, or WinGet not ready yet. Right after
  formatting the Microsoft Store updates App Installer in the background, and meanwhile winget.exe may not
  start ("The file cannot be accessed by the system") or not open its sources. }
function WingetWorthRetry(Launched: Boolean; Code: Integer): Boolean;
begin
  Result := (not Launched) or (Code = WingetInstallInProgress) or (Code = WingetSourceCacheMissing);
end;

function WingetParams(AppIndex: Integer): String;
var
  ID: String;
begin
  ID := AppPackageIDs[AppIndex];
  Result := 'install --id ' + ID + ' -e --source ' + AppSources[AppIndex] +
    ' --silent --disable-interactivity --accept-package-agreements --accept-source-agreements' +
    LocationArg(ID) + LanguageArg(ID);
end;

{ How an app ended, from WinGet's exit code (Launched: winget.exe could start) or from Skipped, the reason
  it was cut ('' if it was not): its row, the counts, the advice and whether it is retried at the end.
  For the apps installed one by one and for those installed several at a time (parallel.iss). }
procedure FinishApp(T, AppIndex: Integer; Launched: Boolean; Code: Integer; const Skipped: String);
var
  ID, Reason, Hint: String;
  Kind: Integer;
  NoCard: Boolean;
begin
  ID := AppPackageIDs[AppIndex];
  Hint := '';
  NoCard := False;
  if Skipped <> '' then
  begin
    Kind := TaskSkipped;
    Reason := Skipped;
    if Reason = CustomMessage('CutByCancel') then
      Hint := CustomMessage('WgCutHint')
    else
      Hint := CustomMessage('WgSkipHint');
  end
  else if not Launched then
  begin
    Kind := TaskFailed;
    Reason := CustomMessage('WgNotLaunched');
    Hint := SysErrorMessage(Code) + ' ' + CustomMessage('WgNotReadyHint');
  end
  else
  begin
    Kind := ClassifyWinget(Code, Reason, Hint);
    if (Code = WingetInstallerFailed) and (InstallerExitCode(T) <> '') then
      Reason := Msg('WgInstallerCode', [InstallerExitCode(T)]);
    { NVIDIA's installers refuse to run without an NVIDIA card (seen in a virtual machine) }
    NoCard := (Kind = TaskFailed) and (Pos('graphics\nvidia', AppComponents[AppIndex]) = 1) and
      (HardwareText <> '') and not NvidiaGpuFound;
    if NoCard then
      Hint := CustomMessage('WgNoNvidia');
  end;
  if (Code = WingetRebootRequired) or (Code = WingetRebootInitiated) then
    RebootNeeded := True;
  { A failure that may come from what was going on at that moment (another installer holding a file or a
    driver, a download, WinGet not ready) gets one more try after the other apps, and no notice until then }
  TaskRetryAtEnd[T] := not RetryingAtEnd and (Kind = TaskFailed) and not NoCard and
    ((not Launched) or (Code = WingetInstallerFailed) or (Code = WingetInstallInProgress) or
     (Code = WingetSourceCacheMissing) or (Code = WingetDownloadFailed) or (Code = WingetNoNetwork) or
     (Code = WingetMissingDependency) or (Code = WingetDependenciesFailed));

  case Kind of
    TaskInstalled: InstalledCount := InstalledCount + 1;
    TaskAlready: AlreadyInstalledCount := AlreadyInstalledCount + 1;
    TaskFailed: FailedCount := FailedCount + 1;
  else
    SkippedCount := SkippedCount + 1;
  end;

  TaskReasons[T] := Reason;
  TaskHints[T] := Hint;
  { To retry it by hand: without Battle.net's language, whose quoting only works in cmd }
  if (Kind = TaskFailed) or (Kind = TaskSkipped) then
    TaskRetry[T] := 'winget install --id ' + ID + ' -e' + LocationArg(ID);
  AddStatusLine('[' + KindText(Kind) + '] ' + AppNames[AppIndex] + ': ' + Reason);
  FinishTask(T, Kind, Reason + ' — ' + IntToStr((GetTickCount - TaskStartTicks[T]) div 1000) + ' s');
  if TaskRetryAtEnd[T] then
  begin
    AddTaskDetail(T, CustomMessage('RetryLaterLine'));
    TaskStates[T] := CustomMessage('StateRetryLater');
    RefreshTaskList;
  end;
end;

{ One app on its own: the status line follows it, Skip cuts it }
procedure InstallApp(T, AppIndex: Integer);
var
  Params: String;
  Code, Attempt: Integer;
  Launched: Boolean;
begin
  StartTask(T, CustomMessage('StateInstalling'));
  InstallDetailLabel.Caption := '';
  AddStatusLine('[INSTALLING] ' + AppNames[AppIndex]);
  Params := WingetParams(AppIndex);
  SkipRequested := False;
  TaskTimeoutMinutes := AppTimeoutMinutes;
  SkipButton.Enabled := True;

  for Attempt := 1 to 3 do
  begin
    if AppAsUser[AppIndex] then
      Launched := RunAsOriginalUser('winget.exe', Params, Code)
    else
      Launched := RunLogged('winget.exe', Params, Code);
    { Certificate rejected: first an updated App Installer; if that is not it, the user may allow the
      Windows check for this run }
    if Launched and (Code = WingetPinnedCertMismatch) and (Attempt < 3) and not SkipRequested and
       not CancelRequested and (UpdateAppInstaller(T) or AllowStoreWithoutPinning(T)) then
      Continue;
    if SkipRequested or CancelRequested or (Attempt = 3) or not WingetWorthRetry(Launched, Code) then
      Break;
    if Launched and (Code = WingetInstallInProgress) then
      AddTaskDetail(T, Msg('BusyRetry', [IntToStr(BusyRetrySeconds)]))
    else
      AddTaskDetail(T, Msg('WingetRetry', [IntToStr(BusyRetrySeconds)]));
    AddStatusLine('[WAITING] ' + AppNames[AppIndex] + ': WinGet busy or not ready (' + IntToStr(Code) + ').');
    WaitSeconds(BusyRetrySeconds);
  end;
  SkipButton.Enabled := False;
  if SkipRequested then
    FinishApp(T, AppIndex, Launched, Code, SkipReason)
  else
    FinishApp(T, AppIndex, Launched, Code, '');
end;

{ Updates everything WinGet knows how to update, apps installed before this run included }
procedure RunUpgradeAllStep(T: Integer);
var
  Code: Integer;
  Launched: Boolean;
begin
  StartTask(T, CustomMessage('StateWorking'));
  StatusBase := CustomMessage('UpgradingAll');
  InstallStatusLabel.Caption := StatusBase;
  InstallDetailLabel.Caption := '';
  SkipRequested := False;
  TaskTimeoutMinutes := UpgradeTimeoutMinutes;
  SkipButton.Enabled := True;
  Launched := RunSystemCommand('winget.exe', 'upgrade --all --silent --disable-interactivity ' +
    '--accept-package-agreements --accept-source-agreements', False, Code);
  SkipButton.Enabled := False;
  if (Code = WingetRebootRequired) or (Code = WingetRebootInitiated) then
    RebootNeeded := True;
  if SkipRequested then
    FinishStep(T, True, 'SumUpgrade', SkipReason, CustomMessage('WgSkipHint'))
  else if Launched and ((Code = 0) or (Code = WingetUpdateNotApplicable) or (Code = WingetRebootRequired)) then
    FinishStep(T, False, 'SumUpgrade', CustomMessage('UpgradeDone'), '')
  else
    FinishStep(T, True, 'SumUpgrade', Msg('UpgradeFailed', [CodeText(Code)]), CustomMessage('UpgradeHint'));
end;
