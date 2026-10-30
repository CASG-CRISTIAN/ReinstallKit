[Code]
{ ---------- Several apps at a time ----------
  The WinGet apps that install as administrator go to scripts\install_parallel.ps1, which runs up to
  ParallelCount winget processes together. Microsoft Store apps and those that install as the user stay
  one by one (installation.iss): the Store has a queue of its own, and its certificate check may need a
  question. Each line the script writes says which job it belongs to. The status line follows the app
  running longest, which is the one Skip cuts. }

var
  PoolActive: Boolean;
  PoolCount, PoolDone: Integer;
  PoolTasks, PoolApps, PoolPids: array of Integer;
  PoolSkips: array of String;   { why the user, Cancel or the time limit cut it; '' if not }
  PoolTarget: Integer;          { the job Skip cuts, -1 if none }
  PoolStopFile: String;
  PoolTimer: Longword;

function InPool(AppIndex: Integer): Boolean;
begin
  Result := (AppSources[AppIndex] = 'winget') and not AppAsUser[AppIndex];
end;

{ Only that winget and what it launched (/T). While it waits to be retried there is no process (pid 0):
  a file tells the script not to start it again. }
procedure KillPoolJob(J: Integer);
var
  Code: Integer;
begin
  if PoolPids[J] > 0 then
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /PID ' + IntToStr(PoolPids[J]), '', SW_HIDE, ewNoWait, Code)
  else
    SaveStringToFile(PoolStopFile + '_' + IntToStr(J), '', False);
end;

procedure PoolSkip(J: Integer; const Reason: String);
begin
  if (J < 0) or (PoolSkips[J] <> '') then
    Exit;
  PoolSkips[J] := Reason;
  AddTaskDetail(PoolTasks[J], Msg('SkipLine', [Reason]));
  AddStatusLine('[SKIP] ' + TaskTitles[PoolTasks[J]] + ': ' + Reason);
  KillPoolJob(J);
end;

procedure PoolSkipClick(Sender: TObject);
begin
  PoolSkip(PoolTarget, CustomMessage('SkippedByUser'));
end;

{ Cancel: no job starts any more and the running ones are cut }
procedure PoolCancel;
var
  J: Integer;
begin
  SaveStringToFile(PoolStopFile, '', False);
  for J := 0 to PoolCount - 1 do
    if TaskKinds[PoolTasks[J]] = TaskRunning then
      PoolSkip(J, CustomMessage('CutByCancel'));
end;

{ Every half second: the status line names the app running longest, with its time, and an app over the
  time limit is skipped, as one by one }
procedure PoolTick(Wnd, uMsg, TimerID, Time: Longword);
var
  J, T, Running, Seconds: Integer;
begin
  PoolTarget := -1;
  Running := 0;
  for J := 0 to PoolCount - 1 do
  begin
    T := PoolTasks[J];
    if TaskKinds[T] <> TaskRunning then
      Continue;
    Running := Running + 1;
    if PoolSkips[J] <> '' then
      Continue;
    if GetTickCount - TaskStartTicks[T] >= AppTimeoutMinutes * 60000 then
      PoolSkip(J, Msg('SkippedTimeout', [IntToStr(AppTimeoutMinutes)]))
    else if (PoolTarget < 0) or (TaskStartTicks[T] < TaskStartTicks[PoolTasks[PoolTarget]]) then
      PoolTarget := J;
  end;
  SkipButton.Enabled := (PoolTarget >= 0) and not CancelRequested;
  if CancelRequested or (PoolTarget < 0) then
    Exit;
  Seconds := (GetTickCount - TaskStartTicks[PoolTasks[PoolTarget]]) div 1000;
  InstallStatusLabel.Caption := Msg('InstallingParallel', [IntToStr(Running), IntToStr(PoolDone),
    IntToStr(PoolCount), AppNames[PoolApps[PoolTarget]]]) + Format('   (%d:%.2d)', [Seconds div 60, Seconds mod 60]);
end;

procedure PoolStarted(J, Pid: Integer);
begin
  PoolPids[J] := Pid;
  { A retry starts again on the same row }
  if TaskKinds[PoolTasks[J]] <> TaskRunning then
  begin
    MarkTaskRunning(PoolTasks[J], CustomMessage('StateInstalling'));
    AddStatusLine('[INSTALLING] ' + AppNames[PoolApps[J]]);
  end;
  { Skipped while it waited to be retried }
  if PoolSkips[J] <> '' then
    KillPoolJob(J);
end;

procedure PoolRetry(J, Code: Integer);
begin
  PoolPids[J] := 0;
  if Code = WingetInstallInProgress then
    AddTaskDetail(PoolTasks[J], Msg('BusyRetry', [IntToStr(BusyRetrySeconds)]))
  else
    AddTaskDetail(PoolTasks[J], Msg('WingetRetry', [IntToStr(BusyRetrySeconds)]));
  AddStatusLine('[WAITING] ' + AppNames[PoolApps[J]] + ': WinGet busy or not ready (' + IntToStr(Code) + ').');
end;

procedure PoolEnded(J: Integer; Launched: Boolean; Code: Integer);
begin
  PoolPids[J] := 0;
  PoolDone := PoolDone + 1;
  FinishApp(PoolTasks[J], PoolApps[J], Launched, Code, PoolSkips[J]);
  StepDone;
end;

{ "<job>|<line>" from install_parallel.ps1: its markers, or WinGet's output for that app's task }
procedure PoolOutput(const S: String; const Error, FirstLine: Boolean);
var
  P, J: Integer;
  Line, Rest: String;
begin
  P := Pos('|', S);
  J := -1;
  if P > 1 then
    J := StrToIntDef(Copy(S, 1, P - 1), -1);
  if (J < 0) or (J >= PoolCount) then
  begin
    { The script's own messages }
    if Trim(S) <> '' then
      LogDetail(Trim(S));
    Exit;
  end;
  Line := ToolLine(Copy(S, P + 1, MaxInt));
  if Line = '' then
    Exit;
  if Copy(Line, 1, 8) = '@@START ' then
    PoolStarted(J, StrToIntDef(Copy(Line, 9, MaxInt), 0))
  else if Copy(Line, 1, 8) = '@@RETRY ' then
  begin
    Rest := Copy(Line, 9, MaxInt);
    PoolRetry(J, StrToIntDef(Copy(Rest, 1, Pos(' ', Rest + ' ') - 1), 0));
  end
  else if Copy(Line, 1, 7) = '@@EXIT ' then
    PoolEnded(J, True, StrToIntDef(Copy(Line, 8, MaxInt), 1359))
  else if Copy(Line, 1, 10) = '@@NOSTART ' then
    PoolEnded(J, False, StrToIntDef(Copy(Line, 11, MaxInt), 1359))
  else
  begin
    InstallDetailLabel.Caption := AppNames[PoolApps[J]] + ': ' + Line;
    if Pos(#$2592, Line) = 0 then
    begin
      LogDetail(AppNames[PoolApps[J]] + ': ' + Line);
      AddTaskDetail(PoolTasks[J], Line);
    end;
  end;
end;

{ Installs the queue's apps that go in the pool, up to Max at a time; their tasks start at FirstAppTask.
  Those it does not get to (Cancel, or the script failed) stay pending for the one-by-one loop. }
procedure RunPool(FirstAppTask, Max: Integer);
var
  I, J, Code: Integer;
  Jobs: TArrayOfString;
  JobsFile, Params: String;
begin
  PoolCount := 0;
  PoolDone := 0;
  for I := 0 to QueueCount - 1 do
    if InPool(InstallQueue[I]) then
      PoolCount := PoolCount + 1;
  { With one app there is nothing to run at the same time }
  if PoolCount < 2 then
  begin
    PoolCount := 0;
    Exit;
  end;
  SetArrayLength(PoolTasks, PoolCount);
  SetArrayLength(PoolApps, PoolCount);
  SetArrayLength(PoolPids, PoolCount);
  SetArrayLength(PoolSkips, PoolCount);
  SetArrayLength(Jobs, PoolCount);
  J := 0;
  for I := 0 to QueueCount - 1 do
    if InPool(InstallQueue[I]) then
    begin
      PoolTasks[J] := FirstAppTask + I;
      PoolApps[J] := InstallQueue[I];
      PoolPids[J] := 0;
      PoolSkips[J] := '';
      Jobs[J] := IntToStr(J) + #9 + WingetParams(InstallQueue[I]);
      J := J + 1;
    end;
  ExtractTemporaryFile('install_parallel.ps1');
  JobsFile := ExpandConstant('{tmp}\parallel_jobs.txt');
  PoolStopFile := ExpandConstant('{tmp}\parallel_stop');
  SaveStringsToUTF8File(JobsFile, Jobs, False);
  DeleteFile(PoolStopFile);

  AddStatusLine('[PARALLEL] ' + IntToStr(PoolCount) + ' apps, up to ' + IntToStr(Max) + ' at a time.');
  InstallHintLabel.Caption := Msg('InstallHintParallel', [IntToStr(AppTimeoutMinutes)]);
  InstallDetailLabel.Caption := '';
  SkipButton.OnClick := @PoolSkipClick;
  PoolTarget := -1;
  PoolActive := True;
  PoolTimer := SetTimer(0, 0, 500, CreateCallback(@PoolTick));
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    AddQuotes(ExpandConstant('{tmp}\install_parallel.ps1')) + ' -Jobs ' + AddQuotes(JobsFile) +
    ' -Max ' + IntToStr(Max) + ' -Stop ' + AddQuotes(PoolStopFile) + ' -RetrySeconds ' +
    IntToStr(BusyRetrySeconds) + ' -Winget ' + AddQuotes('winget.exe');
  LogDetail('> ' + PowerShellExe + ' ' + Params);
  try
    ExecAndLogOutput(PowerShellExe, Params, '', SW_HIDE, ewWaitUntilTerminated, Code, @PoolOutput);
  except
    LogDetail(GetExceptionMessage);
  end;
  KillTimer(0, PoolTimer);
  PoolTimer := 0;
  PoolActive := False;
  SkipButton.OnClick := @SkipButtonClick;
  SkipButton.Enabled := False;
  InstallHintLabel.Caption := Msg('InstallHint', [IntToStr(AppTimeoutMinutes)]);
  { Running when the script ended: cut by Cancel while waiting to be retried, or the script failed (those
    end as not launched, and get their try at the end) }
  for J := 0 to PoolCount - 1 do
    if TaskKinds[PoolTasks[J]] = TaskRunning then
      PoolEnded(J, PoolSkips[J] <> '', 1359);
end;
