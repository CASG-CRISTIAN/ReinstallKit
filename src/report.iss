[Code]
{ ---------- Summary and the Desktop report ---------- }

var
  LogPath: String;
  StartedAt: String;
  StartTick: DWORD;

function UnprocessedCount: Integer;
begin
  Result := QueueCount - InstalledCount - AlreadyInstalledCount - FailedCount - SkippedCount;
end;

function IsProblem(T: Integer): Boolean;
begin
  Result := (TaskKinds[T] = TaskFailed) or (TaskKinds[T] = TaskSkipped) or (TaskKinds[T] = TaskWarning);
end;

{ Groups by reason the tasks that ended in those kinds: "  2 · not updated because it was open" }
function GroupReasons(KindA, KindB: Integer; const Indent: String): String;
var
  Reasons: array[0..MaxTasks - 1] of String;
  Counts: array[0..MaxTasks - 1] of Integer;
  N, T, I: Integer;
begin
  N := 0;
  for T := 0 to TaskCount - 1 do
    if (TaskKinds[T] = KindA) or (TaskKinds[T] = KindB) then
    begin
      I := 0;
      while (I < N) and (Reasons[I] <> TaskReasons[T]) do
        I := I + 1;
      if I = N then
      begin
        Reasons[N] := TaskReasons[T];
        Counts[N] := 0;
        N := N + 1;
      end;
      Counts[I] := Counts[I] + 1;
    end;
  Result := '';
  for I := 0 to N - 1 do
    Result := Result + Indent + IntToStr(Counts[I]) + ' · ' + Reasons[I] + #13#10;
end;

{ Summary of what was requested, with the reasons grouped. Used by the final question, the finished
  page and the report. }
function SummaryText(const Indent: String): String;
var
  I: Integer;
begin
  Result := '';
  if QueueCount > 0 then
  begin
    if QueueCount = 1 then
      Result := Indent + CustomMessage('SumRequestedOne') + #13#10
    else
      Result := Indent + Msg('SumRequested', [IntToStr(QueueCount)]) + #13#10;
    Result := Result + Indent + '  • ' + Msg('SumInstalled', [IntToStr(InstalledCount)]) + #13#10;
    if AlreadyInstalledCount > 0 then
      Result := Result + Indent + '  • ' + Msg('SumAlready', [IntToStr(AlreadyInstalledCount)]) + #13#10 +
        GroupReasons(TaskAlready, TaskAlready, Indent + '      ');
    if FailedCount + SkippedCount > 0 then
      Result := Result + Indent + '  • ' + Msg('SumNotInstalled', [IntToStr(FailedCount + SkippedCount)]) + #13#10 +
        GroupReasons(TaskFailed, TaskSkipped, Indent + '      ');
    if (UnprocessedCount > 0) and (CancelReason <> '') then
      Result := Result + Indent + '  • ' + Msg('SumUnprocessedWhy', [CancelReason, IntToStr(UnprocessedCount)]) + #13#10
    else if UnprocessedCount > 0 then
      Result := Result + Indent + '  • ' + Msg('SumUnprocessed', [IntToStr(UnprocessedCount)]) + #13#10;
  end;
  for I := 0 to StepLines.Count - 1 do
    Result := Result + Indent + StepLines[I] + #13#10;
  if AmdGpuFound then
    Result := Result + Indent + Msg('SumAmd', [CustomMessage('AmdDownloadUrl')]) + #13#10;
  if RebootNeeded then
    Result := Result + Indent + CustomMessage('SumReboot') + #13#10;
end;

function Pad(const S: String; Width: Integer): String;
begin
  Result := S;
  if Length(S) < Width then
    Result := S + StringOfChar(' ', Width - Length(S));
end;

function ElapsedText: String;
var
  Seconds: Integer;
begin
  Seconds := (GetTickCount - StartTick) div 1000;
  Result := Msg('Elapsed', [IntToStr(Seconds div 60), IntToStr(Seconds mod 60)]);
end;

{ Aligned label of the report header: "  PC:          " }
function HeaderLabel(const Name: String): String;
begin
  Result := '  ' + Pad(CustomMessage(Name), 13);
end;

{ Report meant to be read in Notepad: the summary on top, what needs reviewing with its reason and
  advice, a table by task and then the full details of each one. }
procedure WriteReport;
var
  R, Bar, Sep: String;
  T, L: Integer;
  HasProblems: Boolean;
  Hints: TStringList;
begin
  Bar := StringOfChar('=', 78) + #13#10;
  Sep := StringOfChar('-', 78) + #13#10;
  R := Bar +
    '  ' + Msg('ReportTitle', ['{#MyAppName} {#MyAppVersion}']) + #13#10 +
    Bar +
    HeaderLabel('ReportPc') + GetComputerNameString + #13#10;
  if HardwareText <> '' then
    R := R + HeaderLabel('ReportHardware') + HardwareText + #13#10;
  R := R +
    HeaderLabel('ReportStart') + StartedAt + #13#10 +
    HeaderLabel('ReportEnd') + GetDateTimeString(CustomMessage('ReportDateFormat'), '/', ':') +
      '   (' + ElapsedText + ')' + #13#10 +
    HeaderLabel('ReportResult') + InstallStatusLabel.Caption + #13#10 +
    Bar + #13#10 +
    CustomMessage('ReportSummary') + #13#10 + SummaryText('  ');
  if not RebootNeeded then
    R := R + '  ' + CustomMessage('ReportNoReboot') + #13#10;

  HasProblems := False;
  { The same advice for several tasks (every Microsoft Store app, say) is written only the first time }
  Hints := TStringList.Create;
  try
    for T := 0 to TaskCount - 1 do
      if IsProblem(T) then
      begin
        if not HasProblems then
          R := R + #13#10 + CustomMessage('ReportReview') + #13#10;
        HasProblems := True;
        R := R + '  * ' + TaskTitles[T] + ': ' + TaskReasons[T] + #13#10;
        if (TaskHints[T] <> '') and (Hints.IndexOf(TaskHints[T]) < 0) then
        begin
          Hints.Add(TaskHints[T]);
          R := R + '      ' + TaskHints[T] + #13#10;
        end;
        if TaskRetry[T] <> '' then
          R := R + '      ' + Msg('ReportRetry', [TaskRetry[T]]) + #13#10;
      end;
  finally
    Hints.Free;
  end;

  { A title longer than its column still leaves a space before the result }
  R := R + #13#10 + CustomMessage('ReportByTask') + #13#10 +
    '  ' + Pad(CustomMessage('ReportColState'), 20) + Pad(CustomMessage('ReportColTask'), 32) +
    CustomMessage('ReportColResult') + #13#10 +
    '  ' + Pad(StringOfChar('-', 18), 20) + Pad(StringOfChar('-', 30), 32) + StringOfChar('-', 30) + #13#10;
  for T := 0 to TaskCount - 1 do
    R := R + '  ' + Pad(TaskStates[T], 20) + Pad(TaskTitles[T], 31) + ' ' + TaskResults[T] + #13#10;

  R := R + #13#10 + CustomMessage('ReportDetails') + #13#10;
  for T := 0 to TaskCount - 1 do
  begin
    R := R + #13#10 + Sep + TaskTitles[T] + '   [' + TaskStates[T] + ']' + #13#10 + Sep;
    for L := 0 to TaskDetails[T].Count - 1 do
      R := R + '  ' + TaskDetails[T].Strings[L] + #13#10;
  end;

  { With a BOM: Notepad in Windows 10 before 1903 does not detect UTF-8 without one. }
  SaveStringToFile(LogPath, #$EF#$BB#$BF + Utf8Encode(R), False);
end;

procedure OpenLog;
var
  ErrorCode: Integer;
begin
  { Setup is in the foreground and hands that right to the editor, which opens as the normal user. }
  AllowSetForegroundWindow(ASFW_ANY);
  ShellExecAsOriginalUser('open', LogPath, '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;
