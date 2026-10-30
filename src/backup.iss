[Code]
{ ---------- Backup steps: drivers with pnputil, Wi-Fi networks with netsh and the app list with WinGet ---------- }

procedure ShowStepStatus(const StatusKey: String);
begin
  StatusBase := CustomMessage(StatusKey);
  InstallStatusLabel.Caption := StatusBase;
  InstallDetailLabel.Caption := '';
end;

var
  DriverStatus: String;   { the step's status, before the count }
  DriverTotal, DriverDone: Integer;
  { pnputil ends with two lines that close in a number, in the language of Windows: "Total driver
    packages: 524" and "Exported driver packages: 524" (or "Added"). They are the last two numbers seen. }
  PnpTotal, PnpDone: Integer;
  { When importing, each package now in Windows gets a "Published Name: oem12.inf" line, also the ones
    Windows already had: those are not "added" but are not missing either }
  PnpPublished: Integer;
  DevicesChecked: Boolean;   { drivers were restored: the end offers Device Manager }

{ The number a line ends with, or -1 }
function TrailingNumber(const S: String): Integer;
var
  I: Integer;
begin
  I := Length(S);
  while (I > 0) and (S[I] >= '0') and (S[I] <= '9') do
    I := I - 1;
  Result := StrToIntDef(Copy(S, I + 1, Length(S) - I), -1);
end;

function PnpSummaryFound: Boolean;
begin
  Result := (PnpTotal > 0) and (PnpDone >= 0) and (PnpDone <= PnpTotal);
end;

{ Present devices with a problem, the ones Device Manager shows with a yellow triangle, as
  "PNPDeviceID|code|name" lines. Disabled ones (code 22) are left out: that is a choice, not a missing
  driver. If WMI fails, the list stays empty. }
procedure ReadProblemDevices(List: TStringList);
var
  Locator, Wmi, Items, Item: Variant;
  I: Integer;
begin
  List.Clear;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Wmi := Locator.ConnectServer('.', 'root\CIMV2');
    Items := Wmi.ExecQuery('SELECT Name, PNPDeviceID, ConfigManagerErrorCode FROM Win32_PnPEntity ' +
      'WHERE ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 22');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      List.Add(VarText(Item.PNPDeviceID) + '|' + VarText(Item.ConfigManagerErrorCode) + '|' + VarText(Item.Name));
    end;
  except
    Log('Device check failed: ' + GetExceptionMessage);
  end;
end;

{ A line of ReadProblemDevices; a device Windows does not know yet is named by its ID }
procedure SplitDevice(const Entry: String; var ID, Code, Name: String);
var
  P: Integer;
begin
  P := Pos('|', Entry);
  ID := Copy(Entry, 1, P - 1);
  Name := Copy(Entry, P + 1, Length(Entry));
  P := Pos('|', Name);
  Code := Copy(Name, 1, P - 1);
  Name := Copy(Name, P + 1, Length(Name));
  if Name = '' then
    Name := ID;
end;

function HasDevice(List: TStringList; const ID: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to List.Count - 1 do
    if Pos(ID + '|', List[I]) = 1 then
      Result := True;
end;

{ The devices that had a problem before restoring the drivers and work now, and the ones that still
  have one (code 28 = no driver), go to the details from line At on, above pnputil's output; the
  result, to the step's line }
function DeviceSummary(T, At: Integer; Before, After: TStringList): String;
var
  I: Integer;
  ID, Code, Name: String;
begin
  InsertTaskDetail(T, At, Msg('DevicesAtStart', [IntToStr(Before.Count)]));
  for I := 0 to Before.Count - 1 do
  begin
    SplitDevice(Before[I], ID, Code, Name);
    if not HasDevice(After, ID) then
    begin
      At := At + 1;
      InsertTaskDetail(T, At, Msg('DeviceFixed', [Name]));
    end;
  end;
  for I := 0 to After.Count - 1 do
  begin
    SplitDevice(After[I], ID, Code, Name);
    At := At + 1;
    if Code = '28' then
      InsertTaskDetail(T, At, Msg('DeviceNoDriver', [Name]))
    else
      InsertTaskDetail(T, At, Msg('DeviceProblem', [Name, Code]));
  end;
  if After.Count > 0 then
    Result := Msg('DevicesLeft', [IntToStr(After.Count), IntToStr(Before.Count)])
  else if Before.Count > 0 then
    Result := Msg('DevicesFixed', [IntToStr(Before.Count)])
  else
    Result := CustomMessage('DevicesAllOk');
end;

{ Files that match Mask in Dir and its subfolders. Not folders: in an export they are called
  "name.inf_amd64_..." and "*.inf" finds them too. }
function CountFiles(const Dir, Mask: String): Integer;
var
  FindRec: TFindRec;
begin
  Result := 0;
  if FindFirst(AddBackslash(Dir) + Mask, FindRec) then
  try
    repeat
      if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
        Result := Result + 1;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
  if FindFirst(AddBackslash(Dir) + '*', FindRec) then
  try
    repeat
      if ((FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        Result := Result + CountFiles(AddBackslash(Dir) + FindRec.Name, Mask);
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

{ pnputil writes a line as it starts each driver, in the language of Windows: "Exporting driver package:
  oem12.inf (name.inf)" when exporting and "Adding driver package: D:\...\name.inf" when importing }
procedure DriverOutput(const S: String; const Error, FirstLine: Boolean);
var
  Line: String;
  N: Integer;
begin
  ToolOutput(S, Error, FirstLine);
  Line := Lowercase(Trim(S));
  N := TrailingNumber(Line);
  if N >= 0 then
  begin
    PnpTotal := PnpDone;
    PnpDone := N;
  end;
  { DISM, if pnputil could not export them, writes "Exporting 3 of 524 - oem12.inf: ..." }
  if ((BackupMode = BackupExport) and ((Pos('.inf (', Line) > 0) or ((Pos('oem', Line) > 0) and (Pos('.inf:', Line) > 0)))) or
     ((BackupMode = BackupImport) and (Pos('\', Line) > 0) and (Length(Line) > 4) and
      (Copy(Line, Length(Line) - 3, 4) = '.inf')) then
  begin
    DriverDone := DriverDone + 1;
    StatusBase := DriverStatus + '  ' + Msg('DriverCount', [IntToStr(DriverDone), IntToStr(DriverTotal)]);
  end
  else if (BackupMode = BackupImport) and (Pos('\', Line) = 0) and (Pos(' oem', Line) > 0) and
     (Copy(Line, Length(Line) - 3, 4) = '.inf') then
    PnpPublished := PnpPublished + 1;
end;

{ pnputil (ANSI) and DISM (OEM, Oem = True) write in legacy code pages and ExecAndLogOutput reads UTF-8:
  stream_ansi.ps1 converts each line as it comes, so the count and the details move while they work }
function RunStreamed(const FileName, Params: String; Oem: Boolean; var ResultCode: Integer): Boolean;
var
  Arguments: String;
begin
  ExtractTemporaryFile('stream_ansi.ps1');
  LogDetail('> ' + ExtractFileName(FileName) + ' ' + Params);
  Arguments := ' ' + CommandArg(Params);
  if Oem then
    Arguments := Arguments + ' -Oem';
  try
    Result := ExecAndLogOutput(PowerShellExe, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
      AddQuotes(ExpandConstant('{tmp}\stream_ansi.ps1')) + ' ' + AddQuotes(FileName) + Arguments, '',
      SW_SHOWNORMAL, ewWaitUntilTerminated, ResultCode, @DriverOutput);
  except
    LogDetail(GetExceptionMessage);
    ResultCode := 1359; { ERROR_INTERNAL_ERROR }
    Result := False;
  end;
end;

function RunPnpUtil(const Params: String; var ResultCode: Integer): Boolean;
begin
  Result := RunStreamed(ExpandConstant('{sys}\pnputil.exe'), Params, False, ResultCode);
end;

{ Windows' other tool for this: DISM exports the same drivers with code of its own. Into a subfolder, so
  it neither collides with what pnputil saved nor overwrites it; restoring reads every subfolder. }
function ExportWithDism(T: Integer; var Code: Integer): Boolean;
var
  Dir: String;
begin
  Dir := AddBackslash(BackupDir) + DismFolder;
  ForceDirectories(Dir);
  AddTaskDetail(T, CustomMessage('ExportRetryDism'));
  AddStatusLine('[DRIVERS] pnputil could not export them all: retrying with DISM.');
  DriverStatus := CustomMessage('ExportingDriversDism');
  StatusBase := DriverStatus;
  DriverDone := 0;
  Result := RunStreamed(ExpandConstant('{sys}\dism.exe'), '/online /export-driver /destination:' + AddQuotes(Dir),
    True, Code) and (Code = 0);
end;

{ Free space where the backup goes, for the advice when it could not be saved }
function FreeSpaceText(const Dir: String): String;
var
  Free, Total: Int64;
begin
  Result := '?';
  if GetSpaceOnDisk64(AddBackslash(Dir), Free, Total) then
    if Free >= 1073741824 then
      Result := IntToStr(Free div 1073741824) + ' GB'
    else
      Result := IntToStr(Free div 1048576) + ' MB';
end;

{ Exporting copies the drivers added to Windows (oem*.inf): the ones Windows brings itself are on any
  clean install. Importing adds them all to Windows and installs the ones this PC's devices use; to
  show whether it worked, the devices with a problem are compared before and after. }
procedure RunDriverStep(T: Integer);
var
  Params, Summary, Count, Hint: String;
  Code, DetailsTop: Integer;
  Failed, Launched: Boolean;
  Before, After: TStringList;
begin
  Before := TStringList.Create;
  After := TStringList.Create;
  try
    if BackupMode = BackupExport then
    begin
      StartTask(T, CustomMessage('StateExporting'));
      ShowStepStatus('ExportingDrivers');
      ForceDirectories(BackupDir);
      Params := '/export-driver * ' + AddQuotes(BackupDir);
      DriverTotal := CountFiles(ExpandConstant('{win}\INF'), 'oem*.inf');
      AddTaskDetail(T, Msg('DriversToExport', [IntToStr(DriverTotal)]));
    end
    else
    begin
      StartTask(T, CustomMessage('StateImporting'));
      ShowStepStatus('ImportingDrivers');
      Params := '/add-driver ' + AddQuotes(AddBackslash(BackupDir) + '*.inf') + ' /subdirs /install';
      DriverTotal := CountFiles(BackupDir, '*.inf');
      AddTaskDetail(T, Msg('DriversToImport', [IntToStr(DriverTotal)]));
      ReadProblemDevices(Before);
    end;
    DriverStatus := StatusBase;
    DriverDone := 0;
    PnpTotal := -1;
    PnpDone := -1;
    PnpPublished := 0;
    DetailsTop := TaskDetails[T].Count;
    InstallDetailLabel.Caption := CustomMessage('MayTakeMinutes');
    AddStatusLine('[DRIVERS] ' + TaskTitles[T] + ': ' + BackupDir + ' (' + IntToStr(DriverTotal) + ' drivers)');
    InstallProgressBar.Style := npbstMarquee;

    Failed := False;
    Hint := CustomMessage('DriverHint');
    Launched := RunPnpUtil(Params, Code);
    if BackupMode = BackupExport then
    begin
      if Launched and (Code = 0) and not (PnpSummaryFound and (PnpDone < PnpTotal)) then
      begin
        if PnpSummaryFound then
          Summary := Msg('DriversSaved', [IntToStr(PnpDone), IntToStr(PnpTotal), BackupDir])
        else
          Summary := Msg('ExportedTo', [BackupDir]);
      end
      else
      begin
        { pnputil could not, or skipped some without saying so in its exit code: another way }
        if not Launched then
          Count := SysErrorMessage(Code)
        else if Code <> 0 then
          Count := CodeText(Code)
        else
          Count := Msg('DriverCount', [IntToStr(PnpDone), IntToStr(PnpTotal)]);
        if ExportWithDism(T, Code) then
          Summary := Msg('DriversSavedDism', [BackupDir, Count])
        else
        begin
          Failed := True;
          Summary := Msg('ExportFailedBoth', [Count, CodeText(Code)]);
          { pnputil says "invalid data" and DISM "file name too long" (206) when the folder is too deep }
          if (Code = 206) or (DriverPathNeeded(BackupDir) > MaxPathChars) then
            Hint := Msg('ExportPathHint', [IntToStr(Length(BackupDir)), ShortBackupDir(BackupDir)])
          else
            Hint := Msg('ExportHint', [FreeSpaceText(BackupDir)]);
        end;
      end;
    end
    else if not Launched then
    begin
      Failed := True;
      Summary := Msg('PnpUtilFailed', [SysErrorMessage(Code)]);
    end
    else
    begin
      if PnpSummaryFound and (PnpPublished > PnpDone) and (PnpPublished <= PnpTotal) then
        Count := Msg('DriversInWindows', [IntToStr(PnpPublished), IntToStr(PnpTotal), IntToStr(PnpPublished - PnpDone)])
      else if PnpSummaryFound then
        Count := Msg('DriversAdded', [IntToStr(PnpDone), IntToStr(PnpTotal)])
      else
        Count := CustomMessage('Imported');
      case Code of
        0: Summary := Count;
        259: Summary := Msg('ImportedNoneNewer', [Count]);
        1641, 3010:
          begin
            RebootNeeded := True;
            Summary := Msg('ImportedReboot', [Count]);
          end;
      else
        begin
          Failed := True;
          Summary := Msg('ImportPartial', [Count, CodeText(Code)]);
        end;
      end;
    end;

    if BackupMode = BackupImport then
    begin
      DevicesChecked := True;
      ReadProblemDevices(After);
      { A device may still be starting with its new driver: one more look before calling it a problem }
      if After.Count > 0 then
      begin
        WaitSeconds(5);
        ReadProblemDevices(After);
      end;
      Summary := Summary + ' · ' + DeviceSummary(T, DetailsTop, Before, After);
      if After.Count > 0 then
      begin
        Failed := True;
        Hint := CustomMessage('DevicesHint');
      end;
    end;

    InstallProgressBar.Style := npbstNormal;
    InstallDetailLabel.Caption := '';
    FinishStep(T, Failed, 'SumDrivers', Summary, Hint);
    if (BackupMode = BackupExport) and not Failed then
      AddTaskDetail(T, CustomMessage('AfterExportTip'));
  finally
    Before.Free;
    After.Free;
  end;
end;

{ netsh cuts a profile's file path past 127 characters without saying so, and then writes it somewhere
  else. So it works in a short folder of Setup's own: the 8.3 form of a "wifi" folder in Setup's temporary
  folder, private to the user. }
function ShortWifiTemp: String;
begin
  Result := ExpandConstant('{tmp}\') + WifiFolder;
  ForceDirectories(Result);
  Result := GetShortName(Result);
end;

{ Saves the networks with their passwords in clear text: it is what lets "netsh wlan add profile"
  connect again without asking. A PC without Wi-Fi simply saves none. They are exported to the short
  folder and copied to the backup; the temporary ones go at once, they hold the passwords. }
procedure RunWifiExportStep(T: Integer);
var
  FindRec: TFindRec;
  Temp: String;
  Code, Count, Reported, L: Integer;
begin
  StartTask(T, CustomMessage('StateExporting'));
  ShowStepStatus('ExportingWifi');
  ForceDirectories(BackupFile(WifiFolder));
  Temp := ShortWifiTemp;
  RunSystemCommand(ExpandConstant('{sys}\netsh.exe'), 'wlan export profile key=clear folder=' + AddQuotes(Temp),
    False, Code);
  { netsh prints one line per network with the file it wrote, in the language of Windows }
  Reported := 0;
  for L := 0 to TaskDetails[T].Count - 1 do
    if Pos('.xml', Lowercase(TaskDetails[T].Strings[L])) > 0 then
      Reported := Reported + 1;
  Count := 0;
  if FindFirst(Temp + '\*.xml', FindRec) then
  try
    repeat
      if FileCopy(Temp + '\' + FindRec.Name, AddBackslash(BackupFile(WifiFolder)) + FindRec.Name, False) then
        Count := Count + 1;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
  DelTree(Temp, True, True, True);
  if Count < Reported then
    FinishStep(T, True, 'SumWifi', Msg('WifiExportFailed', [IntToStr(Reported - Count), IntToStr(Reported)]),
      Msg('ExportHint', [FreeSpaceText(BackupDir)]))
  else if Count > 0 then
    FinishStep(T, False, 'SumWifi', Msg('WifiExported', [IntToStr(Count)]), '')
  else
    FinishStep(T, False, 'SumWifi', CustomMessage('WifiNone'), '');
end;

{ netsh needs Windows' Wi-Fi service (WlanSvc), which only runs where there is a Wi-Fi adapter. Its state
  through WMI, which does not depend on the language of Windows. }
function WlanServiceRunning: Boolean;
var
  Locator, Wmi, Items, Item: Variant;
begin
  Result := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Wmi := Locator.ConnectServer('.', 'root\CIMV2');
    Items := Wmi.ExecQuery('SELECT State FROM Win32_Service WHERE Name = ''WlanSvc''');
    if Items.Count = 0 then
      Exit;
    Item := Items.ItemIndex(0);
    Result := VarText(Item.State) = 'Running';
  except
    Log('Wi-Fi service check failed: ' + GetExceptionMessage);
  end;
end;

{ Right after the drivers, so the Wi-Fi adapter already has its own; Windows then connects by itself.
  The service may not have started yet with a driver that just arrived: it is started once. If it still
  does not run, the PC has no working Wi-Fi and one clear line says so instead of a failure per network. }
procedure RunWifiImportStep(T: Integer);
var
  FindRec: TFindRec;
  Temp, Profile: String;
  Code, Total, Failed, I: Integer;
begin
  StartTask(T, CustomMessage('StateImporting'));
  ShowStepStatus('ImportingWifi');
  if not WlanServiceRunning then
  begin
    AddStatusLine('[WIFI] WlanSvc is not running: starting it.');
    RunSystemCommand(ExpandConstant('{sys}\sc.exe'), 'start WlanSvc', False, Code);
    for I := 1 to 5 do
      if not WlanServiceRunning then
        WaitSeconds(1);
    if not WlanServiceRunning then
    begin
      FinishStep(T, True, 'SumWifi', Msg('WifiNoService', [IntToStr(WifiProfileCount)]),
        CustomMessage('WifiNoServiceHint'));
      Exit;
    end;
  end;
  Total := 0;
  Failed := 0;
  { netsh reads short paths only too (see ShortWifiTemp): each profile goes through the short folder }
  Temp := ShortWifiTemp;
  if FindFirst(AddBackslash(BackupFile(WifiFolder)) + '*.xml', FindRec) then
  try
    repeat
      Total := Total + 1;
      Profile := Temp + '\' + IntToStr(Total) + '.xml';
      if not FileCopy(AddBackslash(BackupFile(WifiFolder)) + FindRec.Name, Profile, False) or
         not RunSystemCommand(ExpandConstant('{sys}\netsh.exe'), 'wlan add profile filename=' + AddQuotes(Profile) +
           ' user=all', False, Code) or (Code <> 0) then
        Failed := Failed + 1;
      DeleteFile(Profile);
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
  DelTree(Temp, True, True, True);
  if Failed = 0 then
    FinishStep(T, False, 'SumWifi', Msg('WifiImported', [IntToStr(Total)]), '')
  else
    FinishStep(T, True, 'SumWifi', Msg('WifiImportFailed', [IntToStr(Failed), IntToStr(Total)]),
      CustomMessage('WifiImportHint'));
end;

{ Microsoft Store IDs (9N..., XP...) say nothing, so their names are saved next to the list.
  The first line of "winget show" is "Found <name> [<ID>]", with "Found" in the language of Windows. }
procedure SaveStoreAppNames(IDs: TStringList);
var
  Names: TArrayOfString;
  I, L, Code, P: Integer;
  Line: String;
begin
  SetArrayLength(Names, 0);
  for I := 0 to IDs.Count - 1 do
    if Pos('.', IDs[I]) = 0 then
    begin
      RunCaptured('winget.exe', 'show --id ' + IDs[I] + ' -e --source msstore --accept-source-agreements ' +
        '--disable-interactivity', Code);
      for L := 0 to CapturedLines.Count - 1 do
      begin
        Line := CapturedLines[L];
        P := Pos(' [' + IDs[I] + ']', Line);
        if (P > 0) and (Pos(' ', Line) < P) then
        begin
          SetArrayLength(Names, GetArrayLength(Names) + 1);
          Names[GetArrayLength(Names) - 1] := IDs[I] + '=' + Trim(Copy(Line, Pos(' ', Line) + 1, P - Pos(' ', Line) - 1));
          Break;
        end;
      end;
    end;
  SaveStringsToUTF8File(BackupFile(AppNamesFile), Names, False);
end;

{ "winget export" leaves out what it cannot link to a package, one line each: "<text>: <name>", with the
  text in the language of Windows. Some are catalog apps installed another way (Firefox in Spanish,
  Spotify from the Store...), and WinGet installs them all the same. Those whose name matches one catalog
  app, and only one (CatalogAppByName), are saved too. Returns how many. }
function SaveAppsMatchedByName(T: Integer; IDs: TStringList): Integer;
var
  Lines: TArrayOfString;
  Matched: TStringList;
  L, I, Found: Integer;
  Line, Name: String;
  Listed: Boolean;
begin
  Matched := TStringList.Create;
  try
    for L := 0 to TaskDetails[T].Count - 1 do
    begin
      Line := TaskDetails[T].Strings[L];
      if Pos(':', Line) = 0 then
        Continue;
      Name := Trim(Copy(Line, Pos(':', Line) + 1, Length(Line)));
      Found := CatalogAppByName(Name);
      if Found < 0 then
        Continue;
      { Already in the list, or matched by another line (a program and its helper share the name) }
      Listed := False;
      for I := 0 to IDs.Count - 1 do
        if Pos('|' + Lowercase(IDs[I]) + '|', AppAllIDs[Found]) > 0 then
          Listed := True;
      for I := 0 to Matched.Count - 1 do
        if Pos(AppPackageIDs[Found] + '=', Matched[I]) = 1 then
          Listed := True;
      if not Listed then
      begin
        Matched.Add(AppPackageIDs[Found] + '=' + Name);
        AddTaskDetail(T, Msg('AppMatchedByName', [Name, AppNames[Found]]));
      end;
    end;
    Result := Matched.Count;
    if Result > 0 then
    begin
      SetArrayLength(Lines, Result);
      for I := 0 to Result - 1 do
        Lines[I] := Matched[I];
      SaveStringsToUTF8File(BackupFile(AppMatchesFile), Lines, False);
    end;
  finally
    Matched.Free;
  end;
end;

{ "winget export" lists the installed apps that WinGet or the Microsoft Store can install again }
procedure RunAppListExportStep(T: Integer);
var
  IDs: TStringList;
  Code, Matched: Integer;
begin
  StartTask(T, CustomMessage('StateExporting'));
  ShowStepStatus('ExportingAppList');
  InstallDetailLabel.Caption := CustomMessage('MayTakeMinutes');
  ForceDirectories(BackupDir);
  DeleteFile(BackupFile(AppListFile));
  DeleteFile(BackupFile(AppMatchesFile));
  RunLogged('winget.exe', 'export -o ' + AddQuotes(BackupFile(AppListFile)) +
    ' --accept-source-agreements --disable-interactivity', Code);
  IDs := TStringList.Create;
  try
    ReadAppListIDs(BackupFile(AppListFile), IDs);
    if IDs.Count = 0 then
      FinishStep(T, True, 'SumAppList', Msg('AppListFailed', [CodeText(Code)]), CustomMessage('AppListHint'))
    else
    begin
      SaveStoreAppNames(IDs);
      Matched := SaveAppsMatchedByName(T, IDs);
      if Matched > 0 then
        FinishStep(T, False, 'SumAppList', Msg('AppListExportedByName', [IntToStr(IDs.Count), IntToStr(Matched)]), '')
      else
        FinishStep(T, False, 'SumAppList', Msg('AppListExported', [IntToStr(IDs.Count)]), '');
    end;
  finally
    IDs.Free;
  end;
end;
