[Code]
{ ---------- External tools: runs WinGet, PowerShell and others and sends their output to the current task ---------- }

function RunLogged(const FileName, Params: String; var ResultCode: Integer): Boolean;
begin
  LogDetail('> ' + FileName + ' ' + Params);
  try
    Result := ExecAndLogOutput(FileName, Params, '', SW_SHOWNORMAL, ewWaitUntilTerminated,
      ResultCode, @ToolOutput);
  except
    LogDetail(GetExceptionMessage);
    ResultCode := 1359; { ERROR_INTERNAL_ERROR }
    Result := False;
  end;
end;

function RunAsOriginalUser(const FileName, Params: String; var ResultCode: Integer): Boolean;
begin
  LogDetail('> (unelevated user) ' + FileName + ' ' + Params);
  InstallDetailLabel.Caption := CustomMessage('AsUserStatus');
  AddTaskDetail(CurrentTask, CustomMessage('AsUserDetail'));
  try
    Result := ExecAsOriginalUser(FileName, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  except
    LogDetail(GetExceptionMessage);
    ResultCode := 1359; { ERROR_INTERNAL_ERROR }
    Result := False;
  end;
end;

var
  CapturedLines: TStringList;

procedure CaptureOutput(const S: String; const Error, FirstLine: Boolean);
begin
  if Trim(S) <> '' then
    CapturedLines.Add(Trim(S));
end;

{ Runs a tool and keeps its output in CapturedLines instead of showing it }
function RunCaptured(const FileName, Params: String; var ResultCode: Integer): Boolean;
begin
  if CapturedLines = nil then
    CapturedLines := TStringList.Create;
  CapturedLines.Clear;
  LogDetail('> ' + FileName + ' ' + Params);
  try
    Result := ExecAndLogOutput(FileName, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode, @CaptureOutput);
  except
    LogDetail(GetExceptionMessage);
    ResultCode := 1359; { ERROR_INTERNAL_ERROR }
    Result := False;
  end;
end;

{ Every command that changes this PC beyond installing apps (restore point, Wi-Fi networks, Windows
  settings, updates) goes through here. AsUser runs it as the signed-in user, whose settings it changes;
  otherwise its output goes to the current task. }
function RunSystemCommand(const FileName, Params: String; AsUser: Boolean; var ResultCode: Integer): Boolean;
begin
  LogDetail('> (system) ' + FileName + ' ' + Params);
  if not AsUser then
  begin
    Result := RunLogged(FileName, Params, ResultCode);
    Exit;
  end;
  try
    Result := ExecAsOriginalUser(FileName, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  except
    LogDetail(GetExceptionMessage);
    ResultCode := 1359; { ERROR_INTERNAL_ERROR }
    Result := False;
  end;
end;

procedure WaitSeconds(Seconds: Integer);
var
  ResultCode: Integer;
begin
  { timeout.exe as a pause: Exec pumps messages while waiting, so the window stays alive }
  Exec(ExpandConstant('{sys}\timeout.exe'), '/t ' + IntToStr(Seconds) + ' /nobreak', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode);
end;
