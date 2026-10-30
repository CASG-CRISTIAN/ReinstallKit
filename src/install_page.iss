[Code]
{ ---------- Installation page: status, collapsible task list, skip and cancel ---------- }

const
  { The apps (catalog and backup) plus the other steps: restore point, drivers, Wi-Fi, app list,
    Windows settings and updates }
  MaxTasks = {#AppTotal + 206};
  { An app that takes longer is skipped automatically: its installer is almost surely waiting for an answer }
  AppTimeoutMinutes = 10;
  { Updating everything may take a while for good reasons }
  UpgradeTimeoutMinutes = 120;
  { A failure notice closes by itself after this, unless paused }
  NoticeSeconds = 10;

  { How each task is going or how it ended; the visible text (TaskStates) is in the chosen language }
  TaskPending = 0;
  TaskRunning = 1;
  TaskInstalled = 2;
  TaskAlready = 3;    { the app was already installed }
  TaskFailed = 4;
  TaskSkipped = 5;
  TaskDone = 6;       { drivers exported or imported }
  TaskWarning = 7;    { drivers with warnings }
  TaskCancelled = 8;

var
  InstallPage: TWizardPage;
  StatusBand: TPanel;
  StatusIcon: TNewStaticText;
  InstallStatusLabel: TNewStaticText;
  InstallDetailLabel: TNewStaticText;
  SkipButton: TNewButton;
  DevicesButton: TNewButton;   { in Skip's place at the end, after restoring drivers }
  InstallProgressBar: TNewProgressBar;
  TaskList: TNewCheckListBox;
  InstallHintLabel: TNewStaticText;
  StatusBase: String;

  { One collapsible row per task: the driver step and each app }
  TaskCount: Integer;
  TaskTitles: array[0..MaxTasks - 1] of String;
  TaskKinds: array[0..MaxTasks - 1] of Integer;
  TaskStates: array[0..MaxTasks - 1] of String;
  TaskReasons: array[0..MaxTasks - 1] of String;
  TaskResults: array[0..MaxTasks - 1] of String;
  TaskHints: array[0..MaxTasks - 1] of String;
  TaskRetry: array[0..MaxTasks - 1] of String;
  TaskExpanded: array[0..MaxTasks - 1] of Boolean;
  TaskRetryAtEnd: array[0..MaxTasks - 1] of Boolean;  { a failed app that gets another try after the rest }
  TaskDetails: array[0..MaxTasks - 1] of TStringList;
  TaskStartTicks: array[0..MaxTasks - 1] of DWORD;  { when each started: several apps may run at once }
  CurrentTask: Integer;
  TaskStartTick: DWORD;
  TimedStep: Boolean;       { a task is running: the status shows for how long }
  TaskListDirty: Boolean;   { an expanded task got new lines: WizardTick redraws the list }
  SkipRequested: Boolean;
  SkipReason: String;
  TaskTimeoutMinutes: Integer;

  { Run state, shared by every step }
  WizardTimer: Longword;
  ModalOpen: Boolean;
  CancelRequested: Boolean;
  CancelReason: String;
  RebootNeeded: Boolean;
  StepLines: TStringList;   { one summary line per step that is not an app, for the summary and the report }
  StepFailed: Boolean;      { one of those steps ended with a warning }

  { Failure notices: a card over the bottom of the task list, one at a time, that does not stop the queue }
  NoticePanel: TPanel;
  NoticeTitle, NoticeText, NoticeCountdown: TNewStaticText;
  NoticePauseButton, NoticeCloseButton: TNewButton;
  NoticeQueue: TStringList;   { tasks still to show }
  NoticeTimer: Longword;
  NoticeLeftMs: Integer;
  NoticePaused: Boolean;
  ToastsSent: Boolean;        { a Windows notification went out: its keys go when Setup closes }

{ ---------- Collapsible task list ---------- }

function KindText(Kind: Integer): String;
begin
  case Kind of
    TaskInstalled: Result := CustomMessage('StateInstalled');
    TaskAlready: Result := CustomMessage('StateAlready');
    TaskFailed: Result := CustomMessage('StateFailed');
    TaskSkipped: Result := CustomMessage('StateSkipped');
    TaskDone: Result := CustomMessage('StateDone');
    TaskWarning: Result := CustomMessage('StateWarning');
    TaskCancelled: Result := CustomMessage('StateCancelled');
  else
    Result := CustomMessage('StatePending');
  end;
end;

function AddTask(const Title, FirstDetail: String): Integer;
begin
  Result := TaskCount;
  TaskTitles[Result] := Title;
  TaskKinds[Result] := TaskPending;
  TaskStates[Result] := KindText(TaskPending);
  TaskReasons[Result] := '';
  TaskResults[Result] := '';
  TaskHints[Result] := '';
  TaskRetry[Result] := '';
  TaskExpanded[Result] := False;
  TaskRetryAtEnd[Result] := False;
  TaskDetails[Result] := TStringList.Create;
  TaskDetails[Result].Add(FirstDetail);
  TaskCount := TaskCount + 1;
end;

{ TNewCheckListBox cannot collapse rows: it is rebuilt entirely, keeping the scroll position. A + in
  front of a task opens its details and a − closes them (U+2212, as wide as the +). }
procedure RefreshTaskList;
var
  T, L, Row, TopIndex: Integer;
  Sign: String;
begin
  TopIndex := SendMessage(TaskList.Handle, LB_GETTOPINDEX, 0, 0);
  SendMessage(TaskList.Handle, WM_SETREDRAW, 0, 0);
  TaskList.Items.Clear;
  for T := 0 to TaskCount - 1 do
  begin
    if TaskExpanded[T] then
      Sign := '−  '
    else
      Sign := '+  ';
    Row := TaskList.AddGroup(Sign + TaskTitles[T], TaskStates[T], 0, TaskDetails[T]);
    if TaskKinds[T] = TaskRunning then
      TaskList.ItemFontStyle[Row] := [fsBold];
    if TaskExpanded[T] then
      for L := 0 to TaskDetails[T].Count - 1 do
        TaskList.AddGroup(TaskDetails[T].Strings[L], '', 1, TaskDetails[T]);
  end;
  SendMessage(TaskList.Handle, LB_SETTOPINDEX, TopIndex, 0);
  SendMessage(TaskList.Handle, WM_SETREDRAW, 1, 0);
  TaskList.Invalidate;
end;

procedure TaskListClick(Sender: TObject);
var
  T: Integer;
begin
  if TaskList.ItemIndex < 0 then
    Exit;
  { Detail rows carry the same object as their task: clicking them collapses it too. }
  for T := 0 to TaskCount - 1 do
    if TaskList.ItemObject[TaskList.ItemIndex] = TaskDetails[T] then
      TaskExpanded[T] := not TaskExpanded[T];
  { Rebuilding clears the selection, so a second click on the same row counts again. }
  RefreshTaskList;
end;

{ Redrawn by WizardTick, not here: a tool can write hundreds of lines (pnputil writes several per driver) }
procedure AddTaskDetail(T: Integer; const Line: String);
begin
  TaskDetails[T].Add(Line);
  if TaskExpanded[T] then
    TaskListDirty := True;
end;

{ For a result that matters more than the tool's output above it }
procedure InsertTaskDetail(T, Index: Integer; const Line: String);
begin
  TaskDetails[T].Insert(Index, Line);
  if TaskExpanded[T] then
    TaskListDirty := True;
end;

procedure MarkTaskRunning(T: Integer; const State: String);
begin
  TaskKinds[T] := TaskRunning;
  TaskStates[T] := State;
  TaskStartTicks[T] := GetTickCount;
  RefreshTaskList;
end;

{ The task the status line follows, with its timer and the skip button }
procedure StartTask(T: Integer; const State: String);
begin
  CurrentTask := T;
  TaskStartTick := GetTickCount;
  TimedStep := True;
  MarkTaskRunning(T, State);
end;

{ One more task done on the progress bar }
procedure StepDone;
begin
  InstallProgressBar.Position := InstallProgressBar.Position + 1;
end;

{ ---------- Failure notices ---------- }

procedure UpdateNoticeCountdown;
var
  Text: String;
begin
  if NoticePaused then
    Text := CustomMessage('NoticePaused')
  else
    Text := Msg('NoticeClosesIn', [IntToStr((NoticeLeftMs + 999) div 1000)]);
  if NoticeQueue.Count > 0 then
    Text := Text + '   ' + Msg('NoticeMore', [IntToStr(NoticeQueue.Count)]);
  NoticeCountdown.Caption := Text;
end;

{ The task list's height without a notice below it: down to the hint (the window may have been resized) }
function TaskListFullHeight: Integer;
begin
  Result := InstallHintLabel.Top - ScaleY(6) - TaskList.Top;
end;

{ The next notice in the queue, or none: the list gets its height back }
procedure ShowNextNotice;
var
  T: Integer;
begin
  if NoticeQueue.Count = 0 then
  begin
    NoticePanel.Visible := False;
    TaskList.Height := TaskListFullHeight;
    Exit;
  end;
  T := StrToInt(NoticeQueue[0]);
  NoticeQueue.Delete(0);
  NoticeTitle.Caption := TaskTitles[T] + ' — ' + TaskStates[T];
  NoticeText.Caption := TaskReasons[T];
  if TaskHints[T] <> '' then
    NoticeText.Caption := NoticeText.Caption + #13#10 + TaskHints[T];
  NoticeLeftMs := NoticeSeconds * 1000;
  NoticePaused := False;
  NoticePauseButton.Caption := CustomMessage('NoticePause');
  UpdateNoticeCountdown;
  { Its texts as wide as the card is now: a hidden card's labels do not follow a resized window }
  NoticeTitle.Width := NoticePauseButton.Left - NoticeTitle.Left - ScaleX(12);
  NoticeText.Width := NoticeTitle.Width;
  NoticeCountdown.Width := NoticeTitle.Width;
  { The card grows until the text fits (the buttons need 84 px), up to leaving 60 px of list }
  NoticeText.AdjustHeight;
  NoticeCountdown.Top := NoticeText.Top + NoticeText.Height + ScaleY(4);
  NoticePanel.Height := NoticeCountdown.Top + NoticeCountdown.Height + ScaleY(8);
  if NoticePanel.Height < ScaleY(84) then
    NoticePanel.Height := ScaleY(84);
  if NoticePanel.Height > TaskListFullHeight - ScaleY(60) then
    NoticePanel.Height := TaskListFullHeight - ScaleY(60);
  NoticePanel.Top := TaskList.Top + TaskListFullHeight - NoticePanel.Height;
  TaskList.Height := TaskListFullHeight - NoticePanel.Height - ScaleY(8);
  NoticePanel.Visible := True;
end;

procedure NoticeTick(Wnd, uMsg, TimerID, Time: Longword);
begin
  if not NoticePanel.Visible or NoticePaused then
    Exit;
  NoticeLeftMs := NoticeLeftMs - 250;
  if NoticeLeftMs <= 0 then
    ShowNextNotice
  else
    UpdateNoticeCountdown;
end;

procedure NoticePauseClick(Sender: TObject);
begin
  NoticePaused := not NoticePaused;
  if NoticePaused then
    NoticePauseButton.Caption := CustomMessage('NoticeResume')
  else
    NoticePauseButton.Caption := CustomMessage('NoticePause');
  UpdateNoticeCountdown;
end;

procedure NoticeCloseClick(Sender: TObject);
begin
  ShowNextNotice;
end;

{ toast.ps1 as the signed-in user, whose Notification Center and HKCU it is }
procedure RunToastScript(const Args: String; Wait: TExecWait);
var
  Params: String;
  Code: Integer;
begin
  ExtractTemporaryFile('toast.ps1');
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ' +
    AddQuotes(ExpandConstant('{tmp}\toast.ps1')) + Args;
  ExecAsOriginalUser(PowerShellExe, Params, '', SW_HIDE, Wait, Code);
end;

{ Also a Windows notification for each failure and for the end: the Notification Center keeps the list
  for whoever left the installer running. OpenFile: what a click on it opens. }
procedure WindowsNotice(const Title, Text, OpenFile: String; Wait: TExecWait);
var
  Args: String;
begin
  if WizardSilent then
    Exit;
  Args := ' -App ' + CommandArg('{#MyAppName}') + ' -Title ' + CommandArg(Title) + ' -Text ' + CommandArg(Text);
  if OpenFile <> '' then
    Args := Args + ' -Open ' + CommandArg(OpenFile);
  ToastsSent := True;
  RunToastScript(Args, Wait);
end;

{ Why a task failed, with its advice, as soon as it ends: the queue goes on meanwhile }
procedure QueueNotice(T: Integer);
begin
  if WizardSilent then
    Exit;
  WindowsNotice(TaskTitles[T] + ' — ' + TaskStates[T], TaskReasons[T], '', ewNoWait);
  NoticeQueue.Add(IntToStr(T));
  if NoticeTimer = 0 then
    NoticeTimer := SetTimer(0, 0, 250, CreateCallback(@NoticeTick));
  if NoticePanel.Visible then
    UpdateNoticeCountdown
  else
    ShowNextNotice;
end;

procedure FinishTask(T, Kind: Integer; const Summary: String);
begin
  TaskKinds[T] := Kind;
  TaskStates[T] := KindText(Kind);
  TaskResults[T] := Summary;
  TaskDetails[T].Add(Msg('TaskResultLine', [Summary]));
  CurrentTask := -1;
  TimedStep := False;
  RefreshTaskList;
  { What the user skipped or cut needs no notice: they know why. A failure that will be retried waits. }
  if ((Kind = TaskFailed) or (Kind = TaskWarning) or (Kind = TaskSkipped)) and not TaskRetryAtEnd[T] and
     (TaskReasons[T] <> CustomMessage('SkippedByUser')) and (TaskReasons[T] <> CustomMessage('CutByCancel')) then
    QueueNotice(T);
end;

{ Ends a step that is not an app: its row, its line in the summary (SummaryKey's text with the
  result) and, if it went wrong, a warning with advice for the report }
procedure FinishStep(T: Integer; Failed: Boolean; const SummaryKey, Summary, Hint: String);
begin
  TaskReasons[T] := Summary;
  StepLines.Add(Msg(SummaryKey, [Summary]));
  if Failed then
  begin
    StepFailed := True;
    TaskHints[T] := Hint;
    AddStatusLine('[WARNING] ' + TaskTitles[T] + ': ' + Summary);
    FinishTask(T, TaskWarning, Summary);
  end
  else
  begin
    AddStatusLine('[OK] ' + TaskTitles[T] + ': ' + Summary);
    FinishTask(T, TaskDone, Summary);
  end;
end;

{ WinGet draws its spinner (- \ | /) and its progress bars one line per frame: over half of a log. The
  spinner is dropped (''); a bar shows in the status line while it moves, and only the finished one (no ▒
  left) goes to the details and the log. }
function ToolLine(const S: String): String;
begin
  Result := Trim(S);
  if (Length(Result) = 1) and (Pos(Result, '-\|/') > 0) then
    Result := '';
end;

procedure ToolOutput(const S: String; const Error, FirstLine: Boolean);
var
  Line: String;
begin
  Line := ToolLine(S);
  if Line = '' then
    Exit;
  InstallDetailLabel.Caption := Line;
  if Pos(#$2592, Line) > 0 then
    Exit;
  LogDetail(Line);
  if CurrentTask >= 0 then
    AddTaskDetail(CurrentTask, Line);
end;

{ ---------- Skipping an app ---------- }

procedure SkipCurrentApp(const Reason: String);
var
  ResultCode: Integer;
begin
  if SkipRequested or not SkipButton.Enabled then
    Exit;
  SkipRequested := True;
  SkipReason := Reason;
  SkipButton.Enabled := False;
  AddTaskDetail(CurrentTask, Msg('SkipLine', [Reason]));
  AddStatusLine('[SKIP] ' + TaskTitles[CurrentTask] + ': ' + Reason);
  { It kills every winget.exe and whatever it launched (/T), not only ours;
    narrow it down by PID if it ever gets in the way. }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM winget.exe', '', SW_HIDE, ewNoWait, ResultCode);
end;

procedure SkipButtonClick(Sender: TObject);
begin
  SkipCurrentApp(CustomMessage('SkippedByUser'));
end;

{ Device Manager shows with a yellow triangle every device left without a working driver }
procedure DevicesButtonClick(Sender: TObject);
var
  ErrorCode: Integer;
begin
  ShellExec('', 'devmgmt.msc', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

{ While waiting for a process, Exec disables the wizard window: it repaints but ignores
  clicks. This timer re-enables it so tasks can be expanded, skipped or cancelled during the
  installation (Next and Back stay disabled by code). It leaves the window alone while one of our own
  dialogs is open, so as not to break its modality. It also redraws the task list when it has new lines,
  shows how long the current task has been running and skips an app when it goes over the limit. }
procedure WizardTick(Wnd, uMsg, TimerID, Time: Longword);
var
  Seconds: Integer;
begin
  if not ModalOpen then
    EnableWindow(WizardForm.Handle, True);
  if TaskListDirty then
  begin
    TaskListDirty := False;
    RefreshTaskList;
  end;
  if TimedStep then
  begin
    Seconds := (GetTickCount - TaskStartTick) div 1000;
    InstallStatusLabel.Caption := StatusBase + Format('   (%d:%.2d)', [Seconds div 60, Seconds mod 60]);
    if SkipButton.Enabled and (Seconds >= TaskTimeoutMinutes * 60) then
      SkipCurrentApp(Msg('SkippedTimeout', [IntToStr(TaskTimeoutMinutes)]));
  end;
end;

{ ---------- The page ---------- }

procedure CreateInstallPage;
begin
  InstallPage := CreateCustomPage(wpReady, CustomMessage('InstallTitle'), CustomMessage('InstallDescription'));

  { Status band: icon, current task, last line written by the tool and the skip button }
  StatusBand := CreateBand(InstallPage.Surface, 0, 0, InstallPage.SurfaceWidth, '');
  StatusBand.Height := ScaleY(56);
  StatusIcon := CreateGlyph(StatusBand, #$E895, 18, ScaleX(14), ScaleY(14));

  InstallStatusLabel := TNewStaticText.Create(InstallPage);
  InstallStatusLabel.Parent := StatusBand;
  InstallStatusLabel.Font.Style := [fsBold];
  InstallStatusLabel.AutoSize := False;
  InstallStatusLabel.SetBounds(ScaleX(52), ScaleY(10), StatusBand.Width - ScaleX(226), ScaleY(18));
  InstallStatusLabel.Anchors := [akLeft, akTop, akRight];
  InstallStatusLabel.Caption := CustomMessage('Preparing');

  { Last line written by the running tool }
  InstallDetailLabel := TNewStaticText.Create(InstallPage);
  InstallDetailLabel.Parent := StatusBand;
  InstallDetailLabel.AutoSize := False;
  InstallDetailLabel.SetBounds(ScaleX(52), ScaleY(29), InstallStatusLabel.Width, ScaleY(18));
  InstallDetailLabel.Anchors := [akLeft, akTop, akRight];
  InstallDetailLabel.Caption := '';
  MakeMuted(InstallDetailLabel);

  SkipButton := TNewButton.Create(InstallPage);
  SkipButton.Parent := StatusBand;
  SkipButton.SetBounds(StatusBand.Width - ScaleX(162), ScaleY(15), ScaleX(150), ScaleY(26));
  SkipButton.Anchors := [akTop, akRight];
  SkipButton.Caption := CustomMessage('SkipButton');
  SkipButton.Enabled := False;
  SkipButton.OnClick := @SkipButtonClick;

  DevicesButton := TNewButton.Create(InstallPage);
  DevicesButton.Parent := StatusBand;
  DevicesButton.SetBounds(SkipButton.Left, SkipButton.Top, SkipButton.Width, SkipButton.Height);
  DevicesButton.Anchors := [akTop, akRight];
  DevicesButton.Caption := CustomMessage('DevicesButton');
  DevicesButton.Visible := False;
  DevicesButton.OnClick := @DevicesButtonClick;

  InstallProgressBar := TNewProgressBar.Create(InstallPage);
  InstallProgressBar.Parent := InstallPage.Surface;
  InstallProgressBar.SetBounds(0, StatusBand.Height + ScaleY(12), InstallPage.SurfaceWidth, ScaleY(10));
  InstallProgressBar.Anchors := [akLeft, akTop, akRight];

  TaskList := TNewCheckListBox.Create(InstallPage);
  TaskList.Parent := InstallPage.Surface;
  TaskList.ShowLines := True;
  TaskList.OnClick := @TaskListClick;
  TaskList.SetBounds(0, InstallProgressBar.Top + InstallProgressBar.Height + ScaleY(12), InstallPage.SurfaceWidth,
    InstallPage.SurfaceHeight - InstallProgressBar.Top - InstallProgressBar.Height - ScaleY(12) - ScaleY(36));
  TaskList.Anchors := [akLeft, akTop, akRight, akBottom];

  { Failure notice: warning icon, the task, why and the advice; on the right, pause and close }
  NoticeQueue := TStringList.Create;
  NoticePanel := CreateColorPanel(InstallPage.Surface, ThemeColor('#FFF4E5', '#3D2B12'));
  NoticePanel.SetBounds(0, TaskList.Top + TaskList.Height - ScaleY(124), InstallPage.SurfaceWidth, ScaleY(124));
  NoticePanel.Anchors := [akLeft, akRight, akBottom];
  NoticePanel.Visible := False;
  SetTextColor(CreateGlyph(NoticePanel, #$E7BA, 15, ScaleX(13), ScaleY(11)), '#B35900', '#FFB86C');
  NoticeTitle := TNewStaticText.Create(InstallPage);
  NoticeTitle.Parent := NoticePanel;
  NoticeTitle.AutoSize := False;
  NoticeTitle.Font.Style := [fsBold];
  NoticeTitle.SetBounds(ScaleX(46), ScaleY(10), NoticePanel.Width - ScaleX(186), ScaleY(18));
  NoticeTitle.Anchors := [akLeft, akTop, akRight];
  NoticeText := TNewStaticText.Create(InstallPage);
  NoticeText.Parent := NoticePanel;
  NoticeText.AutoSize := False;
  NoticeText.WordWrap := True;
  NoticeText.SetBounds(ScaleX(46), ScaleY(30), NoticeTitle.Width, ScaleY(66));
  NoticeText.Anchors := [akLeft, akTop, akRight];
  NoticeCountdown := TNewStaticText.Create(InstallPage);
  NoticeCountdown.Parent := NoticePanel;
  NoticeCountdown.AutoSize := False;
  NoticeCountdown.SetBounds(ScaleX(46), ScaleY(100), NoticeTitle.Width, ScaleY(16));
  NoticeCountdown.Anchors := [akLeft, akTop, akRight];
  MakeMuted(NoticeCountdown);
  NoticePauseButton := TNewButton.Create(InstallPage);
  NoticePauseButton.Parent := NoticePanel;
  NoticePauseButton.SetBounds(NoticePanel.Width - ScaleX(128), ScaleY(12), ScaleX(116), ScaleY(26));
  NoticePauseButton.Anchors := [akTop, akRight];
  NoticePauseButton.OnClick := @NoticePauseClick;
  NoticeCloseButton := TNewButton.Create(InstallPage);
  NoticeCloseButton.Parent := NoticePanel;
  NoticeCloseButton.SetBounds(NoticePauseButton.Left, ScaleY(46), NoticePauseButton.Width, ScaleY(26));
  NoticeCloseButton.Anchors := [akTop, akRight];
  NoticeCloseButton.Caption := CustomMessage('NoticeClose');
  NoticeCloseButton.OnClick := @NoticeCloseClick;

  InstallHintLabel := TNewStaticText.Create(InstallPage);
  InstallHintLabel.Parent := InstallPage.Surface;
  InstallHintLabel.AutoSize := False;
  InstallHintLabel.WordWrap := True;
  InstallHintLabel.SetBounds(0, InstallPage.SurfaceHeight - ScaleY(30), InstallPage.SurfaceWidth, ScaleY(30));
  InstallHintLabel.Anchors := [akLeft, akRight, akBottom];
  InstallHintLabel.Caption := Msg('InstallHint', [IntToStr(AppTimeoutMinutes)]);
end;
