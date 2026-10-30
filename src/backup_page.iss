[Code]
{ ---------- Backup pages: what to do with this PC's backup (drivers, Wi-Fi networks and app list) and where ---------- }

const
  BackupNone = 0;
  BackupExport = 1;
  BackupImport = 2;
  { Backup folders keep the prefix of the first versions, so older backups are still found }
  BackupPrefix = 'Drivers_';
  AppListFile = 'apps.json';        { "winget export" format, so "winget import" can read it too }
  AppNamesFile = 'apps_names.txt';  { ID=name of the Microsoft Store apps, whose IDs say nothing }
  { ID=installed name of the catalog apps that "winget export" could not link, matched by their name }
  AppMatchesFile = 'apps_by_name.txt';
  WifiFolder = 'wifi';              { one XML per network, from "netsh wlan export profile" }
  DismFolder = 'dism';              { DISM's export, when pnputil could not save them all }
  { Windows' MAX_PATH less its closing null: neither pnputil nor DISM read or write longer paths }
  MaxPathChars = 259;

var
  BackupModePage: TInputOptionWizardPage;
  ExportDirPage: TInputDirWizardPage;
  ImportDirPage: TInputDirWizardPage;
  ExportAppListCheck: TNewCheckBox;
  ExportWifiCheck: TNewCheckBox;
  ImportDriversCheck: TNewCheckBox;
  ImportWifiCheck: TNewCheckBox;
  StoreLongest: Integer;   { longest "\package folder\...\file" of the driver store, once measured }

function BackupMode: Integer;
begin
  Result := BackupModePage.SelectedValueIndex;
end;

function BackupDir: String;
begin
  if BackupMode = BackupExport then
    Result := ExportDirPage.Values[0]
  else
    Result := ImportDirPage.Values[0];
  Result := RemoveBackslashUnlessRoot(Trim(Result));
end;

function BackupFile(const Name: String): String;
begin
  Result := AddBackslash(BackupDir) + Name;
end;

function HasInfFiles(const Dir: String; Depth: Integer): Boolean;
var
  FindRec: TFindRec;
begin
  Result := FindFirst(AddBackslash(Dir) + '*.inf', FindRec);
  if Result then
  begin
    FindClose(FindRec);
    Exit;
  end;
  if (Depth > 0) and FindFirst(AddBackslash(Dir) + '*', FindRec) then
  try
    repeat
      if ((FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and
         (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        Result := HasInfFiles(AddBackslash(Dir) + FindRec.Name, Depth - 1);
    until Result or not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

function WifiProfileCount: Integer;
var
  FindRec: TFindRec;
begin
  Result := 0;
  if FindFirst(AddBackslash(BackupFile(WifiFolder)) + '*.xml', FindRec) then
  try
    repeat
      Result := Result + 1;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

{ Restoring a backup does something besides checking its apps: its drivers or its Wi-Fi networks }
function ImportChosen: Boolean;
begin
  Result := ImportDriversCheck.Checked or (ImportWifiCheck.Checked and (WifiProfileCount > 0));
end;

{ The IDs saved by "winget export": every "PackageIdentifier" value. Microsoft Store IDs have no dot. }
procedure ReadAppListIDs(const FileName: String; IDs: TStringList);
var
  S: AnsiString;
  P: Integer;
begin
  IDs.Clear;
  if not LoadStringFromFile(FileName, S) then
    Exit;
  P := Pos('"PackageIdentifier"', S);
  while P > 0 do
  begin
    Delete(S, 1, P + 18);   { up to the closing quote of the key }
    Delete(S, 1, Pos('"', S));
    IDs.Add(Copy(S, 1, Pos('"', S) - 1));
    Delete(S, 1, Pos('"', S));
    P := Pos('"PackageIdentifier"', S);
  end;
end;

{ Most likely backup next to the installer: this PC's one or, if Windows gave the PC another name
  when reinstalling, the first backup folder found. }
function FindBackup: String;
var
  FindRec: TFindRec;
begin
  Result := AddBackslash(ExpandConstant('{src}')) + BackupPrefix + GetComputerNameString;
  if DirExists(Result) then
    Exit;
  Result := RemoveBackslashUnlessRoot(ExpandConstant('{src}'));
  if FindFirst(AddBackslash(Result) + BackupPrefix + '*', FindRec) then
  try
    repeat
      if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
      begin
        Result := AddBackslash(Result) + FindRec.Name;
        Exit;
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

{ The longest path below Dir, folders included: a folder already too long cannot even be opened }
function LongestPathBelow(const Dir: String): Integer;
var
  FindRec: TFindRec;
  Path: String;
  Len: Integer;
begin
  Result := Length(Dir);
  if FindFirst(Dir + '\*', FindRec) then
  try
    repeat
      if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
      begin
        Path := Dir + '\' + FindRec.Name;
        if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          Len := LongestPathBelow(Path)
        else
          Len := Length(Path);
        if Len > Result then
          Result := Len;
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

{ The longest path that saving the drivers in Dir needs: each package goes in a folder named as in the
  driver store, and DISM's subfolder makes it longer. The whole store is measured, Windows' own drivers
  too: that errs on the safe side, and they are rarely the longest. }
function DriverPathNeeded(const Dir: String): Integer;
var
  Store: String;
begin
  if StoreLongest = 0 then
  begin
    Store := ExpandConstant('{sys}\DriverStore\FileRepository');
    StoreLongest := LongestPathBelow(Store) - Length(Store);
  end;
  Result := Length(AddBackslash(Dir) + DismFolder) + StoreLongest;
end;

{ Where to suggest the backup when the chosen folder is too long: the root of the same drive }
function ShortBackupDir(const Dir: String): String;
begin
  Result := AddBackslash(ExtractFileDrive(Dir)) + BackupPrefix + GetComputerNameString;
end;

{ When Next is clicked on a folder page }
function ValidateBackupDir: Boolean;
var
  Dir, Short: String;
  Needed, Longest: Integer;
begin
  Result := True;
  Dir := BackupDir;
  if Dir = '' then
  begin
    ShowDialog(DialogError, CustomMessage('DirMissingTitle'), CustomMessage('DirMissingText'),
      '', [SetupMessage(msgButtonOK)]);
    Result := False;
  end
  else if BackupMode = BackupExport then
  begin
    Needed := DriverPathNeeded(Dir);
    if Needed > MaxPathChars then
    begin
      { Some drivers would not fit: not saving them all is no backup to format with }
      AddStatusLine('[BACKUP] Folder too long for the drivers: ' + IntToStr(Needed) + ' characters needed, ' + Dir);
      Short := ShortBackupDir(Dir);
      Result := ShowDialog(DialogError, CustomMessage('PathTooLongTitle'),
        Msg('PathTooLongText', [IntToStr(Needed), IntToStr(Length(Dir)), IntToStr(Length(Dir) - Needed + MaxPathChars)]),
        '', [Msg('UseFolder', [Short]), CustomMessage('ChooseOtherFolder')]) = 0;
      if Result then
      begin
        ExportDirPage.Values[0] := Short;
        Result := ValidateBackupDir;
      end;
    end
    else if CompareText(ExtractFileDrive(Dir), ExtractFileDrive(ExpandConstant('{win}'))) = 0 then
      Result := ShowDialog(DialogWarning, Msg('SameDriveTitle', [ExtractFileDrive(Dir)]), CustomMessage('SameDriveText'),
        '', [CustomMessage('SameDriveKeep'), CustomMessage('ChooseOtherFolder')]) = 0;
  end
  else if not DirExists(Dir) then
  begin
    ShowDialog(DialogError, CustomMessage('DirNotFoundTitle'), Dir, '', [SetupMessage(msgButtonOK)]);
    Result := False;
  end
  else
  begin
    Longest := LongestPathBelow(Dir);
    if Longest > MaxPathChars then
    begin
      { Moved somewhere deeper with a tool that copes with long paths: pnputil would not read those files }
      AddStatusLine('[BACKUP] Backup folder too long to read: paths of ' + IntToStr(Longest) + ' characters in ' + Dir);
      ShowDialog(DialogError, CustomMessage('ImportPathTooLongTitle'), Msg('ImportPathTooLongText', [IntToStr(Longest),
        ShortBackupDir(Dir)]), '', [SetupMessage(msgButtonOK)]);
      Result := False;
    end
    else if not HasInfFiles(Dir, 3) and not FileExists(BackupFile(AppListFile)) and (WifiProfileCount = 0) then
      Result := ShowDialog(DialogWarning, CustomMessage('EmptyBackupTitle'), CustomMessage('EmptyBackupText'),
        '', [CustomMessage('ContinueAnyway'), CustomMessage('ChooseOtherFolder')]) = 0;
  end;
end;

function AddPageCheck(Page: TWizardPage; Top: Integer; const Caption: String): TNewCheckBox;
begin
  Result := TNewCheckBox.Create(Page);
  Result.Parent := Page.Surface;
  Result.SetBounds(0, Top, Page.SurfaceWidth, ScaleY(20));
  Result.Anchors := [akLeft, akTop, akRight];
  Result.Caption := Caption;
  Result.Checked := True;
end;

{ The explanation goes in a band with the three options below, each with its moment on the right.
  Then one folder page to export, with what else to save, and another one to import, with what to restore
  (the apps are chosen on the next page). }
procedure CreateBackupPages;
var
  Band: TPanel;
  Backup, Found: String;
  Top: Integer;
begin
  BackupModePage := CreateInputOptionPage(wpWelcome,
    CustomMessage('BackupTitle'), CustomMessage('BackupDescription'), '', True, False);
  BackupModePage.Add(CustomMessage('BackupNone'));
  BackupModePage.Add(CustomMessage('BackupExport'));
  BackupModePage.Add(CustomMessage('BackupImport'));
  BackupModePage.CheckListBox.ItemSubItem[1] := CustomMessage('BackupBeforeFormat');
  BackupModePage.CheckListBox.ItemSubItem[2] := CustomMessage('BackupAfterFormat');
  BackupModePage.SelectedValueIndex := BackupNone;
  Band := CreateBand(BackupModePage.Surface, 0, 0, BackupModePage.SurfaceWidth, #$E88E);
  AddBandText(Band, CustomMessage('BackupInfo') + #13#10#13#10 + CustomMessage('BackupInfoWhat'));
  BackupModePage.SubCaptionLabel.Visible := False;
  BackupModePage.CheckListBox.MinItemHeight := ScaleY(26);
  BackupModePage.CheckListBox.Top := Band.Height + ScaleY(16);
  BackupModePage.CheckListBox.Height := BackupModePage.SurfaceHeight - BackupModePage.CheckListBox.Top;

  ExportDirPage := CreateInputDirPage(BackupModePage.ID,
    CustomMessage('ExportTitle'), CustomMessage('ExportDescription'), '',
    True, BackupPrefix + GetComputerNameString);
  ExportDirPage.Add(CustomMessage('ExportPrompt'));
  ExportDirPage.Values[0] := AddBackslash(ExpandConstant('{src}')) + BackupPrefix + GetComputerNameString;
  AddDirBand(ExportDirPage, #$E88E, CustomMessage('ExportInfo'));
  Top := ExportDirPage.Edits[0].Top + ExportDirPage.Edits[0].Height + ScaleY(22);
  ExportAppListCheck := AddPageCheck(ExportDirPage, Top, CustomMessage('ExportAppList'));
  ExportWifiCheck := AddPageCheck(ExportDirPage, Top + ScaleY(26), CustomMessage('ExportWifi'));

  ImportDirPage := CreateInputDirPage(ExportDirPage.ID,
    CustomMessage('ImportTitle'), CustomMessage('ImportDescription'), '', False, '');
  ImportDirPage.Add(CustomMessage('ImportPrompt'));
  Backup := FindBackup;
  ImportDirPage.Values[0] := Backup;
  if Pos(BackupPrefix, ExtractFileName(Backup)) = 1 then
    Found := Msg('ImportFound', [ExtractFileName(Backup)])
  else
    Found := CustomMessage('ImportHint');
  AddDirBand(ImportDirPage, #$E777, Found + ' ' + CustomMessage('ImportWhat'));
  Top := ImportDirPage.Edits[0].Top + ImportDirPage.Edits[0].Height + ScaleY(22);
  ImportDriversCheck := AddPageCheck(ImportDirPage, Top, CustomMessage('ImportDrivers'));
  ImportWifiCheck := AddPageCheck(ImportDirPage, Top + ScaleY(26), CustomMessage('ImportWifi'));
end;
