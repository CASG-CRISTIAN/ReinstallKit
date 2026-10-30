[Code]
{ ---------- Common: Windows messages and API functions, texts and the internal log ---------- }

const
  WM_SETREDRAW = $000B;
  BM_CLICK = $00F5;
  LB_GETTOPINDEX = $018E;
  LB_SETTOPINDEX = $0197;
  EM_SETMARGINS = $00D3;
  EC_LEFTMARGIN = 1;
  EM_SETCUEBANNER = $1501;
  ASFW_ANY = $FFFFFFFF;

function GetTickCount: DWORD;
  external 'GetTickCount@kernel32.dll stdcall';
function SetTimer(hWnd, nIDEvent, uElapse, lpTimerFunc: Longword): Longword;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd, nIDEvent: Longword): Bool;
  external 'KillTimer@user32.dll stdcall';
function EnableWindow(hWnd: HWND; bEnable: Bool): Bool;
  external 'EnableWindow@user32.dll stdcall';
function AllowSetForegroundWindow(dwProcessId: DWORD): Bool;
  external 'AllowSetForegroundWindow@user32.dll stdcall';
{ For the grey hint text of the search box (EM_SETCUEBANNER) }
function SendTextMessage(Wnd: HWND; uMsg: Cardinal; WParam: Longint; LParam: String): Longint;
  external 'SendMessageW@user32.dll stdcall';

{ Text in the chosen language (lang\*.isl) with its %1, %2... filled in. Texts without placeholders are
  read directly with CustomMessage. Done by hand because FmtMessage rejects the list this function
  receives ("Type Mismatch"); backwards, so that %1 does not touch a %10. }
function Msg(const Name: String; const Args: array of String): String;
var
  I: Integer;
begin
  Result := CustomMessage(Name);
  for I := GetArrayLength(Args) - 1 downto 0 do
    StringChangeEx(Result, '%' + IntToStr(I + 1), Args[I], True);
end;

function PowerShellExe: String;
begin
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

{ One argument of a command line, quoted: inner quotes escaped (\"), line breaks as spaces and a final
  backslash kept away from the closing quote }
function CommandArg(const S: String): String;
begin
  Result := S;
  StringChangeEx(Result, #13#10, ' ', True);
  StringChangeEx(Result, '"', '\"', True);
  if (Result <> '') and (Result[Length(Result)] = '\') then
    Result := Result + ' ';
  Result := '"' + Result + '"';
end;

function CodeText(Code: Integer): String;
begin
  Result := Msg('CodeText', [Format('%.8x', [Code])]);
end;

{ While installing, everything goes to Inno's log (%TEMP%\Setup Log...txt) for troubleshooting.
  The Desktop report is written at the end, sorted and in the chosen language. }
procedure AddStatusLine(const StatusText: String);
begin
  Log(StatusText);
end;

procedure LogDetail(const Text: String);
begin
  Log('    ' + Text);
end;
