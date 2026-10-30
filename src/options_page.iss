[Code]
{ ---------- Options page: suggestions for this PC, restore point, Windows tweaks and updating everything ---------- }

{ The tweaks come from catalog_tweaks.csv (TweaksPath), saved like catalog_apps.csv: ';' separator and
  ANSI encoding. Columns, counting from 0:
     0 Section_ES   1 Id   2 Undo   3 Checked   4 Win11   5 Name_ES   6 Description_ES
     7 Section_EN   8 Name_EN   9 Description_EN   10 Section_FR   11 Name_FR   12 Description_FR
  Id is a tweak of scripts\winutil_tweaks.json (WinUtil's) or scripts\custom_tweaks.json (ours); Undo=Yes
  applies it the way WinUtil turns a toggle off; Win11=Yes offers it only on Windows 11. They are applied
  in this order. }
#sub EmitTweak
  #expr CsvLine = Trim(FileRead(CsvHandle))
  #if Pos("Ã", CsvLine)
    #error catalog_tweaks.csv is saved as UTF-8: save it from Excel as "CSV (delimitado por comas)" so accented letters survive
  #endif
  #if CsvLine != ""
    #if Field(CsvLine, 0) != LastSection
      #expr LastSection = Field(CsvLine, 0)
  AddOptionGroup(Pick({#Langs(0, 7, 10)}));
    #endif
  AddTweak({#Q(1)}, {#IsYes(Field(CsvLine, 2)) ? "True" : "False"}, {#IsYes(Field(CsvLine, 3)) ? "True" : "False"},
    {#IsYes(Field(CsvLine, 4)) ? "True" : "False"}, Pick({#Langs(5, 8, 11)}), Pick({#Langs(6, 9, 12)}));
  #endif
#endsub

const
  { The most of the Windows drive that System Protection may use when Setup turns it on }
  RestoreSpacePercent = 5;
  OneDriveTweak = 'RemoveOneDrive';
  { The least free space of a drive suggested for the user's folders }
  FoldersMinFreeGB = 20;
  { The most apps installed at a time that can be chosen }
  MaxParallel = 4;

var
  OneDriveDropped: Boolean;                 { OneDrive left the app list for the tweak that removes it }
  FoldersDrive: String;                     { 'D:': another drive suggested for the user's folders, or '' }
  OptionsPage: TWizardPage;
  OptionsList: TNewCheckListBox;
  OptionName, OptionDesc: TNewStaticText;   { what the selected row does }
  RowDescriptions: TStringList;             { one per row of OptionsList, empty for the group titles }
  OptRestorePoint, OptUpgradeAll, OptFolders: Integer;  { rows of OptionsList (-1: not offered) }
  OptParallelGroup: Integer;                { its title; "one at a time" follows, then 2 to MaxParallel }
  ProtectionAgreed: Boolean;                { the user said yes to turning System Protection on }
  { The Windows tweaks offered on this PC, in the order they are applied }
  TweakRows: array of Integer;
  TweakIDs: array of String;
  TweakUndo: array of Boolean;
  TweakNames: array of String;

{ Silent installs apply no option: nobody has seen them }
function OptionChecked(Row: Integer): Boolean;
begin
  Result := (Row >= 0) and OptionsList.Checked[Row] and not WizardSilent;
end;

function RestorePointChosen: Boolean;
begin
  Result := OptionChecked(OptRestorePoint);
end;

{ Windows lists the drives with System Protection on in SPP\Clients, one "...(C%3A)" per drive (read the
  way Microsoft's ComputerManagementDsc does). Only an administrator can read it, as Setup is. }
function SystemProtectionOn: Boolean;
var
  Drives: String;
begin
  Result := RegQueryMultiStringValue(HKLM64, 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients',
    '{09F7EDC5-294E-4180-AF6A-FB0E6A0E9513}', Drives) and
    (Pos(Uppercase(Copy(ExpandConstant('{sd}'), 1, 1)) + '%3A', Uppercase(Drives)) > 0);
end;

function UpgradeAllChosen: Boolean;
begin
  Result := OptionChecked(OptUpgradeAll);
end;

function FoldersChosen: Boolean;
begin
  Result := OptionChecked(OptFolders);
end;

{ How many apps are installed at a time: 1 in silent mode, where options are not applied }
function ParallelCount: Integer;
var
  K: Integer;
begin
  Result := 1;
  for K := 2 to MaxParallel do
    if OptionChecked(OptParallelGroup + K) then
      Result := K;
end;

{ How many apps at a time this PC takes well: 3 with 8 logical processors and 16 GB of RAM, 2 with 4 and
  8 GB, 1 otherwise; and 1 in a virtual machine, whose disk, network and processors its host shares. Why
  says what it is based on. }
function RecommendedParallel(var Why: String): Integer;
var
  Locator, Wmi, Items, Item: Variant;
  Processors: Integer;
  GB: Int64;
  Maker: String;
begin
  Result := 1;
  Why := '';
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Wmi := Locator.ConnectServer('.', 'root\CIMV2');
    Items := Wmi.ExecQuery('SELECT Manufacturer, Model, NumberOfLogicalProcessors, TotalPhysicalMemory ' +
      'FROM Win32_ComputerSystem');
    Item := Items.ItemIndex(0);
    Maker := Uppercase(VarText(Item.Manufacturer) + ' ' + VarText(Item.Model));
    Processors := Item.NumberOfLogicalProcessors;
    { A 64-bit number comes as text; Windows keeps part of the RAM, so it is rounded }
    GB := (StrToInt64Def(VarText(Item.TotalPhysicalMemory), 0) + 536870912) div 1073741824;
    if (Pos('VIRTUAL', Maker) > 0) or (Pos('VMWARE', Maker) > 0) or (Pos('QEMU', Maker) > 0) or
       (Pos('KVM', Maker) > 0) or (Pos('XEN', Maker) > 0) or (Pos('PARALLELS', Maker) > 0) then
      Why := CustomMessage('ParallelWhyVm')
    else
    begin
      Why := Msg('ParallelWhyPc', [IntToStr(Processors), IntToStr(GB)]);
      if (Processors >= 8) and (GB >= 16) then
        Result := 3
      else if (Processors >= 4) and (GB >= 8) then
        Result := 2;
    end;
  except
    Log('PC check for parallel installs failed: ' + GetExceptionMessage);
  end;
  Log('Apps at a time recommended: ' + IntToStr(Result) + ' (' + Why + ')');
end;

{ Another drive of this PC for the user's folders: not Windows' one, nor on a USB, SD or MMC disk or a
  virtual disk file; of the rest, the one with most free space, if it has FoldersMinFreeGB. Text describes
  it ("D: (HDD, 812 GB libres)"). '' if there is none or the storage WMI provider does not answer. }
function DetectFoldersDrive(var Text: String): String;
var
  Locator, Wmi, Items, Item: Variant;
  I, Letter, Disk, Bus: Integer;
  Disks: TStringList;
  Drive, Kind: String;
  Free, Total, Best: Int64;
begin
  Result := '';
  Best := FoldersMinFreeGB;
  Best := Best * 1073741824;
  Disks := TStringList.Create;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Wmi := Locator.ConnectServer('.', 'root\Microsoft\Windows\Storage');
    { "disk number=media type" (3 HDD, 4 SSD) of the disks that may hold them }
    Items := Wmi.ExecQuery('SELECT DeviceId, MediaType, BusType FROM MSFT_PhysicalDisk');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      Bus := Item.BusType;
      if (Bus <> 7) and (Bus <> 12) and (Bus <> 13) and (Bus <> 15) then
        Disks.Add(VarText(Item.DeviceId) + '=' + IntToStr(Item.MediaType));
    end;
    Items := Wmi.ExecQuery('SELECT DriveLetter, DiskNumber FROM MSFT_Partition');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      Letter := Item.DriveLetter;
      Disk := Item.DiskNumber;
      Kind := ListValue(Disks, IntToStr(Disk));
      if (Letter < Ord('A')) or (Kind = '') then
        Continue;
      Drive := Chr(Letter) + ':';
      if (CompareText(Drive, ExtractFileDrive(ExpandConstant('{win}'))) <> 0) and
         GetSpaceOnDisk64(Drive + '\', Free, Total) and (Free > Best) then
      begin
        Best := Free;
        Result := Drive;
        if Kind = '3' then
          Kind := 'HDD, '
        else if Kind = '4' then
          Kind := 'SSD, '
        else
          Kind := '';
        Text := Msg('DriveFree', [Drive, Kind, IntToStr(Free div 1073741824)]);
      end;
    end;
  except
    Log('Drive detection failed: ' + GetExceptionMessage);
  end;
  Disks.Free;
  Log('Drive suggested for the user''s folders: ' + Result);
end;

function ChosenTweakCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to GetArrayLength(TweakRows) - 1 do
    if OptionChecked(TweakRows[I]) then
      Result := Result + 1;
end;

{ "Uninstall OneDrive" and OneDrive in the app list (a backup brings it) undo each other: the tweak runs
  first and the app would put it back. The user chooses: without the app (the ready page says so) or
  without the tweak. }
procedure DropAppsUndoneByTweaks;
var
  I, A, Row: Integer;
  Changes: String;
begin
  Row := -1;
  for I := 0 to GetArrayLength(TweakIDs) - 1 do
    if (TweakIDs[I] = OneDriveTweak) and not TweakUndo[I] and OptionChecked(TweakRows[I]) then
      Row := TweakRows[I];
  { Unticked again, the app stays unticked: the user may tick it back on the apps page }
  if Row < 0 then
  begin
    OneDriveDropped := False;
    Exit;
  end;
  for A := 0 to AppCount - 1 do
    if (Pos('|microsoft.onedrive|', AppAllIDs[A]) > 0) and AppIsSelected(A) then
    begin
      if ShowDialog(DialogQuestion, CustomMessage('OneDriveConflictTitle'), CustomMessage('OneDriveConflictText'),
        '', [CustomMessage('OneDriveRemove'), CustomMessage('OneDriveKeep')]) = 0 then
      begin
        Changes := '';
        MarkApp(A, False, Changes);
        ApplyChanges(Changes);
        OneDriveDropped := True;
        Log('App dropped for the tweak ' + OneDriveTweak + ': ' + AppPackageIDs[A]);
      end
      else
      begin
        OptionsList.Checked[Row] := False;
        Log('Tweak ' + OneDriveTweak + ' unticked to keep ' + AppPackageIDs[A]);
      end;
      Exit;
    end;
end;

function AnyOptionChosen: Boolean;
begin
  Result := RestorePointChosen or UpgradeAllChosen or FoldersChosen or (ChosenTweakCount > 0);
end;

function IsWindows11: Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := Version.Build >= 22000;
end;

function AddOption(const Caption, Description: String; Checked: Boolean): Integer;
begin
  Result := OptionsList.AddCheckBox(Caption, '', 1, Checked, True, False, False, nil);
  RowDescriptions.Add(Description);
end;

procedure AddOptionGroup(const Caption: String);
begin
  OptionsList.ItemFontStyle[OptionsList.AddGroup(Caption, '', 0, nil)] := [fsBold];
  RowDescriptions.Add('');
end;

procedure AddTweak(const ID: String; Undo, Checked, Win11Only: Boolean; const Caption, Description: String);
var
  N: Integer;
begin
  if Win11Only and not IsWindows11 then
    Exit;
  N := GetArrayLength(TweakIDs);
  SetArrayLength(TweakIDs, N + 1);
  SetArrayLength(TweakUndo, N + 1);
  SetArrayLength(TweakNames, N + 1);
  SetArrayLength(TweakRows, N + 1);
  TweakIDs[N] := ID;
  TweakUndo[N] := Undo;
  TweakNames[N] := Caption;
  TweakRows[N] := AddOption(Caption, Description, Checked);
end;

procedure OptionsListClick(Sender: TObject);
var
  R: Integer;
begin
  R := OptionsList.ItemIndex;
  if (R < 0) or (RowDescriptions[R] = '') then
  begin
    OptionName.Caption := '';
    OptionDesc.Caption := CustomMessage('OptionHint');
  end
  else
  begin
    OptionName.Caption := OptionsList.ItemCaption[R];
    OptionDesc.Caption := RowDescriptions[R];
  end;
end;

{ Ticking the restore point with System Protection off: turning it on stays on afterwards, so it is the
  user's call, asked here and not halfway through an installation left running. No unticks it. }
procedure OptionsListClickCheck(Sender: TObject);
begin
  if not OptionsList.Checked[OptRestorePoint] or ProtectionAgreed or SystemProtectionOn then
    Exit;
  ProtectionAgreed := ShowDialog(DialogQuestion, CustomMessage('ProtectionTitle'),
    Msg('ProtectionText', [ExpandConstant('{sd}')]) + #13#10#13#10 +
    Msg('ProtectionAction', [IntToStr(RestoreSpacePercent) + ' %']),
    '', [CustomMessage('ProtectionYes'), CustomMessage('ProtectionNo')]) = 0;
  if not ProtectionAgreed then
    OptionsList.Checked[OptRestorePoint] := False;
end;

{ The checked tweaks are WinUtil's standard selection plus what most people want after formatting }
procedure CreateOptionsPage;
var
  Band, Detail: TPanel;
  DriveText, Why, Caption: String;
  K, Recommended: Integer;
begin
  OptionsPage := CreateCustomPage(wpSelectComponents, CustomMessage('OptionsTitle'), CustomMessage('OptionsDescription'));
  Band := CreateBand(OptionsPage.Surface, 0, 0, OptionsPage.SurfaceWidth, #$E713);
  AddBandText(Band, CustomMessage('OptionsInfo'));

  { What the selected row does: its name and a description of up to two lines }
  Detail := CreateBand(OptionsPage.Surface, 0, OptionsPage.SurfaceHeight - ScaleY(64), OptionsPage.SurfaceWidth, '');
  Detail.Height := ScaleY(64);
  Detail.Anchors := [akLeft, akRight, akBottom];
  OptionName := AddDetailLine(Detail, 0);
  OptionName.Font.Style := [fsBold];
  OptionDesc := AddDetailLine(Detail, 1);
  OptionDesc.WordWrap := True;
  OptionDesc.Height := ScaleY(32);

  OptionsList := TNewCheckListBox.Create(OptionsPage);
  OptionsList.Parent := OptionsPage.Surface;
  OptionsList.MinItemHeight := ScaleY(22);
  OptionsList.SetBounds(0, Band.Height + ScaleY(12), OptionsPage.SurfaceWidth,
    Detail.Top - Band.Height - ScaleY(20));
  OptionsList.Anchors := [akLeft, akTop, akRight, akBottom];
  OptionsList.OnClick := @OptionsListClick;
  OptionsList.OnClickCheck := @OptionsListClickCheck;
  RowDescriptions := TStringList.Create;

  { Suggestions that depend on this PC, first, only when they apply }
  OptFolders := -1;
  FoldersDrive := DetectFoldersDrive(DriveText);
  if FoldersDrive <> '' then
  begin
    AddOptionGroup(CustomMessage('OptGroupSuggestions'));
    OptFolders := AddOption(Msg('OptFolders', [DriveText]), Msg('OptFoldersDesc', [FoldersDrive]), False);
  end;
  { How many apps at a time, with the one this PC takes well already chosen }
  Recommended := RecommendedParallel(Why);
  AddOptionGroup(CustomMessage('OptGroupParallel'));
  OptParallelGroup := OptionsList.Items.Count - 1;
  for K := 1 to MaxParallel do
  begin
    if K = 1 then
      Caption := CustomMessage('OptParallelOne')
    else
      Caption := Msg('OptParallelMany', [IntToStr(K)]);
    if K = Recommended then
      Caption := Msg('OptParallelRecommended', [Caption]);
    OptionsList.AddRadioButton(Caption, '', 1, K = Recommended, True, nil);
    RowDescriptions.Add(Msg('OptParallelDesc', [Why]));
  end;
  AddOptionGroup(CustomMessage('OptGroupBefore'));
  OptRestorePoint := AddOption(CustomMessage('OptRestorePoint'), CustomMessage('OptRestorePointDesc'), False);
  { Generated from catalog_tweaks.csv }
#expr CsvHandle = FileOpen(TweaksPath)
#if !CsvHandle
  #error Cannot open catalog_tweaks.csv
#endif
#expr FileRead(CsvHandle)
#expr LastSection = ""
#for {0; !FileEof(CsvHandle); 0} EmitTweak
#expr FileClose(CsvHandle)
  AddOptionGroup(CustomMessage('OptGroupAfter'));
  OptUpgradeAll := AddOption(CustomMessage('OptUpgradeAll'), CustomMessage('OptUpgradeAllDesc'), False);
  OptionsListClick(nil);
end;

{ The chosen options for the ready page, one per line under their group (a group without any is left out) }
function ChosenOptionsText(const Space, NewLine: String): String;
var
  R: Integer;
  Group: String;
begin
  Result := '';
  Group := '';
  for R := 0 to OptionsList.Items.Count - 1 do
    if RowDescriptions[R] = '' then
      Group := OptionsList.ItemCaption[R]
    { How many at a time only says something with two apps or more }
    else if OptionChecked(R) and not ((R > OptParallelGroup) and (R <= OptParallelGroup + MaxParallel) and
       (CountSelectedApplications < 2)) then
    begin
      if Group <> '' then
        Result := Result + Space + Group + NewLine;
      Group := '';
      Result := Result + Space + Space + OptionsList.ItemCaption[R] + NewLine;
    end;
end;
