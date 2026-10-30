[Code]
{ ---------- Windows: the restore point and the tweaks of the options page ---------- }

{ If a restore point was created in the last 24 hours, Windows does not create another one and says
  so with a warning that mentions "1440" (minutes) in any language. }
procedure RunRestorePointStep(T: Integer);
var
  Code, SizeCode, L: Integer;
  Recent, TurnOn: Boolean;
  Drive: String;
begin
  StartTask(T, CustomMessage('StateWorking'));
  StatusBase := CustomMessage('CreatingRestorePoint');
  InstallStatusLabel.Caption := StatusBase;
  InstallDetailLabel.Caption := CustomMessage('MayTakeMinutes');
  InstallProgressBar.Style := npbstMarquee;
  Drive := ExpandConstant('{sd}');
  { Off until now: the user agreed to turn it on when ticking the option (options_page.iss) }
  TurnOn := not SystemProtectionOn;
  if not RunSystemCommand(PowerShellExe, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' +
    '"Enable-ComputerRestore -Drive ''' + Drive + '\''; ' +
    'Checkpoint-Computer -Description ''{#MyAppName}'' -RestorePointType MODIFY_SETTINGS"', False, Code) then
    Code := -1;
  if TurnOn and (Code = 0) then
  begin
    { Only what Setup turned on gets a limit: a System Protection set up by the user is left as it was }
    InsertTaskDetail(T, 0, Msg('ProtectionHowToOff', [Drive]));
    if RunSystemCommand(ExpandConstant('{sys}\vssadmin.exe'), 'Resize ShadowStorage /For=' + Drive + ' /On=' + Drive +
      ' /MaxSize=' + IntToStr(RestoreSpacePercent) + '%', False, SizeCode) and (SizeCode = 0) then
      InsertTaskDetail(T, 0, Msg('ProtectionLimit', [IntToStr(RestoreSpacePercent) + ' %']));
  end
  else if TurnOn and SystemProtectionOn then
    { No restore point after all: System Protection goes back off, as it was }
    RunSystemCommand(PowerShellExe, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' +
      '"Disable-ComputerRestore -Drive ''' + Drive + '\''"', False, SizeCode);
  InstallProgressBar.Style := npbstNormal;
  InstallDetailLabel.Caption := '';
  Recent := False;
  for L := 0 to TaskDetails[T].Count - 1 do
    if Pos('1440', TaskDetails[T].Strings[L]) > 0 then
      Recent := True;
  if Code <> 0 then
    FinishStep(T, True, 'SumRestore', Msg('RestoreFailed', [CodeText(Code)]), CustomMessage('RestoreHint'))
  else if Recent then
    FinishStep(T, False, 'SumRestore', CustomMessage('RestoreRecent'), '')
  else if TurnOn then
    FinishStep(T, False, 'SumRestore', CustomMessage('RestoreTurnedOn'), '')
  else
    FinishStep(T, False, 'SumRestore', CustomMessage('RestoreCreated'), '');
end;

{ "Uninstall OneDrive" stops Explorer to free its files, and Windows normally starts it again by itself.
  If a few seconds later there is still no taskbar and desktop, it is started here as the signed-in user:
  started elevated, everything opened from it would be elevated too. }
procedure EnsureExplorerRunning;
var
  Locator, Wmi: Variant;
  I, Code: Integer;
  Running: Boolean;
begin
  Running := True;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Wmi := Locator.ConnectServer('.', 'root\CIMV2');
    for I := 1 to 5 do
    begin
      Running := Wmi.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name = ''explorer.exe''').Count > 0;
      if Running then
        Break;
      WaitSeconds(1);
    end;
  except
    Log('Explorer check failed: ' + GetExceptionMessage);
  end;
  if Running then
    Exit;
  AddStatusLine('[TWEAKS] Explorer did not come back by itself: started again.');
  ExecAsOriginalUser(ExpandConstant('{win}\explorer.exe'), '', '', SW_SHOWNORMAL, ewNoWait, Code);
end;

{ The first error a tweak printed (apply_tweaks.ps1 starts them with "!"), from detail line First on,
  as " (error)"; '' if it printed none }
function TweakError(T, First: Integer): String;
var
  L: Integer;
begin
  Result := '';
  for L := First to TaskDetails[T].Count - 1 do
    if Copy(TaskDetails[T].Strings[L], 1, 1) = '!' then
    begin
      Result := ' (' + Trim(Copy(TaskDetails[T].Strings[L], 2, MaxInt)) + ')';
      Exit;
    end;
end;

{ One elevated PowerShell per tweak (scripts\apply_tweaks.ps1, which applies WinUtil's definitions): each
  one's result is known and a failure does not stop the rest. Its output goes to the task, and the summary
  names the tweaks that failed, with their first error. }
procedure RunTweaksStep(T: Integer);
var
  I, Total, Done, Failed, Code, First: Integer;
  Params, Problems: String;
begin
  StartTask(T, CustomMessage('StateWorking'));
  ExtractTemporaryFile('apply_tweaks.ps1');
  ExtractTemporaryFile('winutil_tweaks.json');
  ExtractTemporaryFile('custom_tweaks.json');
  Total := ChosenTweakCount;
  Done := 0;
  Failed := 0;
  Problems := '';
  for I := 0 to GetArrayLength(TweakIDs) - 1 do
    if OptionChecked(TweakRows[I]) and not CancelRequested then
    begin
      Done := Done + 1;
      StatusBase := Msg('ApplyingTweakCount', [IntToStr(Done), IntToStr(Total), TweakNames[I]]);
      InstallStatusLabel.Caption := StatusBase;
      InstallDetailLabel.Caption := '';
      Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
        AddQuotes(ExpandConstant('{tmp}\apply_tweaks.ps1')) + ' -Id ' + TweakIDs[I];
      if TweakUndo[I] then
        Params := Params + ' -Undo';
      First := TaskDetails[T].Count;
      if RunSystemCommand(PowerShellExe, Params, False, Code) and (Code = 0) then
        AddTaskDetail(T, Msg('TweakApplied', [TweakNames[I]]))
      else
      begin
        Failed := Failed + 1;
        Problems := Problems + '; ' + TweakNames[I] + TweakError(T, First);
        AddTaskDetail(T, Msg('TweakFailed', [TweakNames[I]]));
      end;
    end;
  EnsureExplorerRunning;
  AddTaskDetail(T, CustomMessage('TweaksRestartNote'));
  if Failed = 0 then
    FinishStep(T, False, 'SumTweaks', Msg('TweaksApplied', [IntToStr(Done)]), '')
  else
    FinishStep(T, True, 'SumTweaks', Msg('TweaksSomeFailed', [IntToStr(Failed), IntToStr(Done),
      Copy(Problems, 3, MaxInt)]), CustomMessage('TweaksHint'));
end;

{ The suggestion of the options page: Documents, Downloads, Pictures, Videos and Music of the signed-in
  user on another drive (scripts\move_user_folders.ps1, elevated; its output goes to the task) }
procedure RunFoldersStep(T: Integer);
var
  Code: Integer;
begin
  StartTask(T, CustomMessage('StateWorking'));
  StatusBase := CustomMessage('MovingFolders');
  InstallStatusLabel.Caption := StatusBase;
  InstallDetailLabel.Caption := '';
  ExtractTemporaryFile('move_user_folders.ps1');
  if not RunSystemCommand(PowerShellExe, '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    AddQuotes(ExpandConstant('{tmp}\move_user_folders.ps1')) + ' -Drive ' + FoldersDrive, False, Code) then
    Code := -1;
  AddTaskDetail(T, CustomMessage('FoldersUndo'));
  if Code = 0 then
    FinishStep(T, False, 'SumFolders', Msg('FoldersMoved', [FoldersDrive]), '')
  else
    FinishStep(T, True, 'SumFolders', CustomMessage('FoldersFailed'), CustomMessage('FoldersHint'));
end;
