[Code]
{ ---------- Apps page ----------
  Rebuilds Inno's components page: a toolbar (search, profiles, save and load), sections on the left
  and, on the right, the list and the details panel of the selected app. Inno's own component list
  stays hidden and still stores the selection of catalog apps, so /COMPONENTS, /SAVEINF and /LOADINF
  keep working. Apps that come from a backup and are not in the catalog keep theirs in ExtraChecked. }

const
  { Categories of the left column; 0 and up are catalog sections }
  CatBackup = -3;
  CatRecommended = -2;
  CatAll = -1;
  { A profile shown on the right (-10 - profile index); it has no row on the left }
  CatProfileBase = -10;
  ProfileCount = 4;
  { Apps of a backup that never go in the list: runtimes and frameworks Windows installs by itself, and
    classic Teams, which Microsoft retired (the new one is Microsoft.Teams) }
  BackupSkipPrefixes = '|microsoft.ui.xaml.|microsoft.vclibs.|microsoft.windowsappruntime.|microsoft.appinstaller|microsoft.desktopappinstaller|microsoft.dotnet.native.|microsoft.teams.classic|';
  { Apps of a backup that other programs installed as their part (runtimes, database drivers, game
    libraries): they are listed unchecked, since the program that needs one installs it again }
  BackupPartPrefixes = '|microsoft.vcredist.|microsoft.dotnet.runtime.|microsoft.dotnet.aspnetcore.|microsoft.msodbcsql.|microsoft.sqlserver.oledbdriver|microsoft.sqlserver.2012.nativeclient|microsoft.gameinput|nvidia.physx|epicgames.epiconlineservices|python.launcher|';

var
  SearchEdit: TNewEdit;
  ProfileCombo: TNewComboBox;
  SaveButton: TNewButton;
  LoadButton: TNewButton;
  SectionList: TNewCheckListBox;
  SideCats: array of Integer;    { SectionList row -> CatBackup, CatRecommended, CatAll or a section }
  AppList: TNewCheckListBox;
  RowApps: array of Integer;     { AppList row -> app, or -1 for headings and notices }
  AppChecked: array[0..MaxApps - 1] of Boolean;
  ExtraChecked: array[0..MaxApps - 1] of Boolean;  { selection of the backup apps outside the catalog }
  AppInBackup: array[0..MaxApps - 1] of Boolean;
  BackupAppCount: Integer;
  CurrentCat: Integer;
  ListTitle: TNewStaticText;
  ListCount: TNewStaticText;
  ListLinks: TNewLinkLabel;
  DetailName: TNewStaticText;
  DetailBadge: TPanel;           { where the app is installed from, next to its name }
  DetailSource: TNewStaticText;
  DetailDesc: TNewStaticText;
  DetailMeta: TNewStaticText;
  DetailWhy: TNewStaticText;
  DetailNote: TNewStaticText;
  FooterLabel: TNewStaticText;
  AmdButton: TNewButton;

  InstallQueue: array[0..MaxApps - 1] of Integer;
  QueueCount: Integer;

procedure AmdButtonClick(Sender: TObject);
var
  ErrorCode: Integer;
begin
  ShellExecAsOriginalUser('open', CustomMessage('AmdDownloadUrl'), '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

function ProfileKey(P: Integer): String;
begin
  case P of
    0: Result := 'basic';
    1: Result := 'gaming';
    2: Result := 'office';
  else
    Result := 'dev';
  end;
end;

function ProfileName(P: Integer): String;
begin
  case P of
    0: Result := CustomMessage('ProfileBasic');
    1: Result := CustomMessage('ProfileGaming');
    2: Result := CustomMessage('ProfileOffice');
  else
    Result := CustomMessage('ProfileDev');
  end;
end;

{ Lets the search ignore case and accents.
  Only the Spanish and French accents; add others if a new language needs them. }
function Norm(const S: String): String;
begin
  Result := AnsiLowercase(S);
  StringChangeEx(Result, 'á', 'a', True);
  StringChangeEx(Result, 'à', 'a', True);
  StringChangeEx(Result, 'â', 'a', True);
  StringChangeEx(Result, 'é', 'e', True);
  StringChangeEx(Result, 'è', 'e', True);
  StringChangeEx(Result, 'ê', 'e', True);
  StringChangeEx(Result, 'ë', 'e', True);
  StringChangeEx(Result, 'í', 'i', True);
  StringChangeEx(Result, 'î', 'i', True);
  StringChangeEx(Result, 'ï', 'i', True);
  StringChangeEx(Result, 'ó', 'o', True);
  StringChangeEx(Result, 'ô', 'o', True);
  StringChangeEx(Result, 'ú', 'u', True);
  StringChangeEx(Result, 'ù', 'u', True);
  StringChangeEx(Result, 'û', 'u', True);
  StringChangeEx(Result, 'ü', 'u', True);
  StringChangeEx(Result, 'ñ', 'n', True);
  StringChangeEx(Result, 'ç', 'c', True);
end;

function Searching: Boolean;
begin
  Result := Trim(SearchEdit.Text) <> '';
end;

{ A search or a profile: views with no row of their own on the left }
function TransientView: Boolean;
begin
  Result := Searching or (CurrentCat <= CatProfileBase);
end;

function InCategory(A, Cat: Integer): Boolean;
begin
  if Cat <= CatProfileBase then
    Result := Pos(' ' + ProfileKey(CatProfileBase - Cat) + ' ', AppProfiles[A]) > 0
  else if Cat = CatBackup then
    Result := AppInBackup[A]
  else if Cat = CatRecommended then
    Result := Recommended[A]
  else
    Result := (Cat = CatAll) or (AppSection[A] = Cat);
end;

{ Whether the app goes in the right-hand list: it matches the search or belongs to the chosen category }
function IsListed(A: Integer): Boolean;
var
  Query: String;
begin
  if Searching then
  begin
    Query := Norm(Trim(SearchEdit.Text));
    Result := (Pos(Query, Norm(AppNames[A])) > 0) or (Pos(Query, Norm(SectionNames[AppSection[A]])) > 0);
  end
  else
    Result := InCategory(A, CurrentCat);
end;

{ The selection of catalog apps lives in Inno's hidden list, that of other backup apps in ExtraChecked;
  both are copied here to draw and count }
procedure ReadSelection;
var
  A: Integer;
begin
  for A := 0 to AppCount - 1 do
    if AppComponents[A] <> '' then
      AppChecked[A] := WizardIsComponentSelected(AppComponents[A])
    else
      AppChecked[A] := ExtraChecked[A];
end;

{ Checks or unchecks apps in both places; Changes collects the catalog ones as "name,!name" }
procedure MarkApp(A: Integer; Value: Boolean; var Changes: String);
begin
  if AppComponents[A] = '' then
    ExtraChecked[A] := Value
  else if Value then
    Changes := Changes + ',' + AppComponents[A]
  else
    Changes := Changes + ',!' + AppComponents[A];
end;

procedure ApplyChanges(const Changes: String);
begin
  if Changes <> '' then
    WizardSelectComponents(Copy(Changes, 2, Length(Changes)));
end;

{ "checked/total" of a category, for the left column }
function CountText(Cat: Integer): String;
var
  A, Marked, Total: Integer;
begin
  Marked := 0;
  Total := 0;
  for A := 0 to AppCount - 1 do
    if InCategory(A, Cat) then
    begin
      Total := Total + 1;
      if AppChecked[A] then
        Marked := Marked + 1;
    end;
  Result := IntToStr(Marked) + '/' + IntToStr(Total);
end;

procedure RefreshCounts;
var
  A, R, Marked, Listed: Integer;
begin
  for R := 0 to SectionList.Items.Count - 1 do
    SectionList.ItemSubItem[R] := CountText(SideCats[R]);
  Marked := 0;
  Listed := 0;
  for R := 0 to AppList.Items.Count - 1 do
    if RowApps[R] >= 0 then
    begin
      Listed := Listed + 1;
      if AppChecked[RowApps[R]] then
        Marked := Marked + 1;
    end;
  ListCount.Caption := Msg('ListCount', [IntToStr(Marked), IntToStr(Listed)]);
  Marked := 0;
  for A := 0 to AppCount - 1 do
    if AppChecked[A] then
      Marked := Marked + 1;
  FooterLabel.Caption := Msg('FooterCount', [IntToStr(Marked), IntToStr(AppCount)]);
end;

{ Details panel: the name with its source next to it, the description, the ID, why it is recommended and the note }
procedure ShowDetail(A: Integer);
var
  Meta: String;
begin
  DetailBadge.Visible := A >= 0;
  if A < 0 then
  begin
    DetailName.Caption := '';
    DetailDesc.Caption := CustomMessage('DetailHint');
    DetailMeta.Caption := '';
    DetailWhy.Caption := '';
    DetailNote.Caption := '';
    Exit;
  end;
  DetailName.Caption := AppNames[A];
  if AppSources[A] = 'msstore' then
    DetailSource.Caption := CustomMessage('SourceStore')
  else
    DetailSource.Caption := CustomMessage('SourceWinget');
  DetailBadge.SetBounds(DetailName.Left + DetailName.Width + ScaleX(8), DetailName.Top + ScaleY(1),
    DetailSource.Width + ScaleX(14), DetailSource.Height + ScaleY(2));
  DetailDesc.Caption := AppDescriptions[A];
  if AppAsUser[A] then
    Meta := CustomMessage('InstallsAsUser')
  else
    Meta := CustomMessage('InstallsAsAdmin');
  DetailMeta.Caption := AppPackageIDs[A] + ' · ' + Meta;
  if Recommended[A] then
    DetailWhy.Caption := Msg('RecommendedBecause', [RecommendReasons[A]])
  else
    DetailWhy.Caption := '';
  DetailNote.Caption := AppNotes[A];
  { Without a recommendation the note moves up to its line }
  if DetailWhy.Caption = '' then
    DetailNote.Top := DetailWhy.Top
  else
    DetailNote.Top := DetailWhy.Top + DetailWhy.Height;
end;

procedure AddRow(A: Integer);
begin
  SetArrayLength(RowApps, GetArrayLength(RowApps) + 1);
  RowApps[GetArrayLength(RowApps) - 1] := A;
end;

{ Fills the right-hand list. "All" is grouped by section; while searching, each row shows its section. }
procedure FillAppList;
var
  A, Row, LastSection, First: Integer;
  Level: Byte;
  Grouped, Tagged: Boolean;
  Sub: String;
begin
  Grouped := (not Searching) and (CurrentCat = CatAll);
  Level := 0;
  if Grouped then
    Level := 1;
  SendMessage(AppList.Handle, WM_SETREDRAW, 0, 0);
  AppList.Items.Clear;
  SetArrayLength(RowApps, 0);
  LastSection := -1;
  First := -1;
  for A := 0 to AppCount - 1 do
    if IsListed(A) then
    begin
      if Grouped and (AppSection[A] <> LastSection) then
      begin
        LastSection := AppSection[A];
        Row := AppList.AddGroup(SectionNames[LastSection], '', 0, nil);
        AppList.ItemFontStyle[Row] := [fsBold];
        AddRow(-1);
      end;
      { "Recommended" on the right, except in the recommended list itself; while searching, the section }
      Tagged := Recommended[A] and (Searching or (CurrentCat <> CatRecommended));
      Sub := '';
      if Tagged then
        Sub := CustomMessage('RecommendedTag')
      else if Searching then
        Sub := SectionNames[AppSection[A]];
      Row := AppList.AddCheckBox(AppNames[A], Sub, Level, AppChecked[A], True, False, False, nil);
      if Tagged then
        AppList.SubItemFontStyle[Row] := [fsBold];
      AddRow(A);
      if First < 0 then
        First := A;
    end;
  if First < 0 then
  begin
    AppList.AddGroup(Msg('NoSearchResults', [Trim(SearchEdit.Text)]), '', 0, nil);
    AddRow(-1);
  end;
  SendMessage(AppList.Handle, WM_SETREDRAW, 1, 0);
  AppList.Invalidate;

  if Searching then
    ListTitle.Caption := Msg('SearchResults', [Trim(SearchEdit.Text)])
  else if CurrentCat <= CatProfileBase then
    ListTitle.Caption := Msg('ProfileTitle', [ProfileName(CatProfileBase - CurrentCat)])
  else if CurrentCat = CatBackup then
    ListTitle.Caption := CustomMessage('ListBackup')
  else if CurrentCat = CatRecommended then
    ListTitle.Caption := CustomMessage('ListRecommended')
  else if CurrentCat = CatAll then
    ListTitle.Caption := CustomMessage('ListAll')
  else
    ListTitle.Caption := SectionNames[CurrentCat];
  ShowDetail(First);
end;

{ Marks the category in use on the left, with its radio button. A search or a profile has no row there, so
  "All" is marked. No row is left selected: TNewCheckListBox draws a selected row without its text once
  the list loses the focus (the section vanished when an app was ticked), and with none selected any click
  on the column arrives at SectionListClick. }
procedure MarkSection;
var
  R: Integer;
begin
  for R := 0 to SectionList.Items.Count - 1 do
  begin
    if ((SideCats[R] = CurrentCat) and not TransientView) or ((SideCats[R] = CatAll) and TransientView) then
      SectionList.Checked[R] := True;
    if SectionList.Checked[R] or (SideCats[R] < 0) then
      SectionList.ItemFontStyle[R] := [fsBold]
    else
      SectionList.ItemFontStyle[R] := [];
  end;
  SectionList.ItemIndex := -1;
end;

procedure UpdateAppPage;
begin
  ReadSelection;
  MarkSection;
  FillAppList;
  RefreshCounts;
end;

procedure SearchEditChange(Sender: TObject);
begin
  UpdateAppPage;
end;

{ A click on a row shows its category (MarkSection leaves none selected, so every click arrives). Choosing
  a section ends the search; clearing the text already refreshes the page through OnChange. }
procedure SectionListClick(Sender: TObject);
begin
  if SectionList.ItemIndex >= 0 then
  begin
    CurrentCat := SideCats[SectionList.ItemIndex];
    if Searching then
      SearchEdit.Text := ''
    else
      UpdateAppPage;
  end;
end;

{ Passes the checkboxes that changed on the right to the selection }
procedure AppListClickCheck(Sender: TObject);
var
  R: Integer;
  Changes: String;
begin
  Changes := '';
  for R := 0 to AppList.Items.Count - 1 do
    if (RowApps[R] >= 0) and (AppList.Checked[R] <> AppChecked[RowApps[R]]) then
      MarkApp(RowApps[R], AppList.Checked[R], Changes);
  ApplyChanges(Changes);
  ReadSelection;
  RefreshCounts;
end;

procedure AppListClick(Sender: TObject);
begin
  if (AppList.ItemIndex >= 0) and (RowApps[AppList.ItemIndex] >= 0) then
    ShowDetail(RowApps[AppList.ItemIndex]);
end;

{ "Select all" and "None": they only affect what the right-hand list shows }
procedure ListLinksClick(Sender: TObject; const Link: String; LinkType: TSysLinkType);
var
  R: Integer;
begin
  for R := 0 to AppList.Items.Count - 1 do
    if RowApps[R] >= 0 then
      AppList.Checked[R] := Link = 'all';
  AppListClickCheck(AppList);
end;

{ A profile checks its apps (on top of what was already checked) and shows them }
procedure ProfileComboChange(Sender: TObject);
var
  A, P: Integer;
  Changes: String;
begin
  P := ProfileCombo.ItemIndex - 1;
  if P < 0 then
    Exit;
  ProfileCombo.ItemIndex := 0;
  CurrentCat := CatProfileBase - P;
  Changes := '';
  for A := 0 to AppCount - 1 do
    if InCategory(A, CurrentCat) then
      MarkApp(A, True, Changes);
  ApplyChanges(Changes);
  if Searching then
    SearchEdit.Text := ''
  else
    UpdateAppPage;
end;

{ Saves the checked catalog apps in Inno's own format, so /LOADINF can read the file too }
procedure SaveButtonClick(Sender: TObject);
var
  FileName, List: String;
  A: Integer;
begin
  FileName := CustomMessage('SelectionFileName');
  if not GetSaveFileName(CustomMessage('SaveSelectionPrompt'), FileName, ExpandConstant('{src}'),
    CustomMessage('SelectionFilter'), 'inf') then
    Exit;
  ReadSelection;
  List := '';
  for A := 0 to CatalogCount - 1 do
    if AppChecked[A] then
      List := List + ',' + AppComponents[A];
  if not SetIniString('Setup', 'Components', Copy(List, 2, Length(List)), FileName) then
    ShowDialog(DialogError, CustomMessage('SelectionSaveFailed'), FileName, '', [SetupMessage(msgButtonOK)]);
end;

{ Replaces the selection of catalog apps with the one in the file }
procedure LoadButtonClick(Sender: TObject);
var
  FileName, List, Changes: String;
  A: Integer;
begin
  FileName := '';
  if not GetOpenFileName(CustomMessage('LoadSelectionPrompt'), FileName, ExpandConstant('{src}'),
    CustomMessage('SelectionFilter'), 'inf') then
    Exit;
  List := ',' + Lowercase(GetIniString('Setup', 'Components', '', FileName)) + ',';
  Changes := '';
  for A := 0 to CatalogCount - 1 do
    MarkApp(A, Pos(',' + Lowercase(AppComponents[A]) + ',', List) > 0, Changes);
  ApplyChanges(Changes);
  UpdateAppPage;
end;

procedure AddSection(const Caption: String; Cat: Integer);
begin
  SectionList.AddRadioButton(Caption, '', 0, Cat = CurrentCat, True, nil);
  SetArrayLength(SideCats, GetArrayLength(SideCats) + 1);
  SideCats[GetArrayLength(SideCats) - 1] := Cat;
end;

{ Fills the left column, each time the page is shown: a backup may have been read in between.
  It starts with the backup's apps or the recommended ones, when there are any. }
procedure FillSectionList;
var
  S: Integer;
begin
  { The first time, the recommended apps (unless a backup's were already chosen by ApplyBackupApps) }
  if (GetArrayLength(SideCats) = 0) and (CurrentCat <> CatBackup) then
  begin
    CurrentCat := CatAll;
    if RecommendedCount > 0 then
      CurrentCat := CatRecommended;
  end;
  { A category that no longer exists, because another backup folder was chosen }
  if ((CurrentCat = CatBackup) and (BackupAppCount = 0)) or (CurrentCat >= SectionCount) then
    CurrentCat := CatAll;
  SectionList.Items.Clear;
  SetArrayLength(SideCats, 0);
  if BackupAppCount > 0 then
    AddSection(CustomMessage('SideBackup'), CatBackup);
  if RecommendedCount > 0 then
    AddSection(CustomMessage('SideRecommended'), CatRecommended);
  AddSection(CustomMessage('SideAll'), CatAll);
  for S := 0 to SectionCount - 1 do
    AddSection(SectionNames[S], S);
  AmdButton.Visible := AmdGpuFound;
  if AmdGpuFound then
    SectionList.Height := AmdButton.Top - ScaleY(8) - SectionList.Top;
end;

{ ---------- Apps from a backup ---------- }

{ Whether ID starts with one of the '|'-separated Prefixes (lowercase) }
function IdHasPrefix(const ID, PrefixList: String): Boolean;
var
  P: Integer;
  Prefixes, Prefix: String;
begin
  Result := False;
  Prefixes := PrefixList;
  Delete(Prefixes, 1, 1);
  while (Prefixes <> '') and not Result do
  begin
    P := Pos('|', Prefixes);
    Prefix := Copy(Prefixes, 1, P - 1);
    Delete(Prefixes, 1, P);
    Result := Copy(Lowercase(ID), 1, Length(Prefix)) = Prefix;
  end;
end;

{ A program's name without what changes from one install to another: from " (", ":" or a version on.
  "Mozilla Firefox (x64 es-ES)" and "Spotify: música y pódcasts" become "Mozilla Firefox" and "Spotify". }
function BaseAppName(const Name: String): String;
var
  I: Integer;
begin
  Result := Trim(Name);
  for I := 2 to Length(Result) do
    if ((Result[I] = '(') and (Result[I - 1] = ' ')) or (Result[I] = ':') or
       ((Result[I] >= '0') and (Result[I] <= '9') and (Result[I - 1] = ' ')) then
    begin
      Result := Trim(Copy(Result, 1, I - 1));
      Exit;
    end;
end;

{ The catalog app with that name (compared by BaseAppName), if exactly one has it; -1 otherwise }
function CatalogAppByName(const Name: String): Integer;
var
  A, Hits: Integer;
  Base: String;
begin
  Result := -1;
  Base := Lowercase(BaseAppName(Name));
  if Base = '' then
    Exit;
  Hits := 0;
  for A := 0 to CatalogCount - 1 do
    if Lowercase(BaseAppName(AppNames[A])) = Base then
    begin
      Result := A;
      Hits := Hits + 1;
    end;
  if Hits <> 1 then
    Result := -1;
end;

{ The value of a "key=value" line (TStringList.Values does not exist in Pascal Script) }
function ListValue(List: TStringList; const Key: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to List.Count - 1 do
    if Pos(Key + '=', List[I]) = 1 then
    begin
      Result := Copy(List[I], Length(Key) + 2, Length(List[I]));
      Exit;
    end;
end;

{ Reads the app list of the backup in Dir: catalog apps found in it get checked, and the others are
  added (checked) to an extra section. Undoes what a previous call added, in case the folder changed. }
procedure ApplyBackupApps(const Dir: String);
var
  IDs, Names: TStringList;
  I, A, Found: Integer;
  ID, Changes: String;
begin
  AppCount := CatalogCount;
  SectionCount := CatalogSectionCount;
  BackupAppCount := 0;
  for A := 0 to MaxApps - 1 do
    AppInBackup[A] := False;
  IDs := TStringList.Create;
  Names := TStringList.Create;
  try
    ReadAppListIDs(AddBackslash(Dir) + AppListFile, IDs);
    { Plus the catalog apps WinGet could not link when saving, matched by their name (backup.iss) }
    if FileExists(AddBackslash(Dir) + AppMatchesFile) then
    begin
      Names.LoadFromFile(AddBackslash(Dir) + AppMatchesFile);
      for I := 0 to Names.Count - 1 do
        if Pos('=', Names[I]) > 1 then
          IDs.Add(Copy(Names[I], 1, Pos('=', Names[I]) - 1));
      Names.Clear;
    end;
    if IDs.Count = 0 then
      Exit;
    if FileExists(AddBackslash(Dir) + AppNamesFile) then
      Names.LoadFromFile(AddBackslash(Dir) + AppNamesFile);
    NewSection(CustomMessage('BackupOtherSection'));
    Changes := '';
    for I := 0 to IDs.Count - 1 do
    begin
      ID := IDs[I];
      Found := -1;
      for A := 0 to CatalogCount - 1 do
        if Pos('|' + Lowercase(ID) + '|', AppAllIDs[A]) > 0 then
          Found := A;
      { A Store ID for an app the catalog installs from elsewhere (Teams, OBS...): its saved name tells.
        Without this the same app would be installed twice. }
      if (Found < 0) and (ListValue(Names, ID) <> '') then
      begin
        Found := CatalogAppByName(ListValue(Names, ID));
        if Found >= 0 then
          Log('Backup app matched by name: ' + ID + ' = ' + AppPackageIDs[Found]);
      end;
      if Found >= 0 then
      begin
        if not AppInBackup[Found] then
          BackupAppCount := BackupAppCount + 1;
        AppInBackup[Found] := True;
        MarkApp(Found, True, Changes);
      end
      else if IdHasPrefix(ID, BackupSkipPrefixes) then
        Log('Backup app skipped (Windows component or retired): ' + ID)
      else if AppCount >= MaxApps then
        Log('Backup app left out (no room): ' + ID)
      else
      begin
        A := AppCount;
        AppComponents[A] := '';
        AppPackageIDs[A] := ID;
        AppAllIDs[A] := '|' + Lowercase(ID) + '|';
        AppProfiles[A] := '';
        AppNotes[A] := '';
        if Pos('.', ID) > 0 then
        begin
          AppSources[A] := 'winget';
          AppAsUser[A] := False;
        end
        else
        begin
          AppSources[A] := 'msstore';
          AppAsUser[A] := True;
        end;
        AppNames[A] := ListValue(Names, ID);
        if AppNames[A] = '' then
          AppNames[A] := ID;
        AppSection[A] := SectionCount - 1;
        AppInBackup[A] := True;
        ExtraChecked[A] := not IdHasPrefix(ID, BackupPartPrefixes);
        if ExtraChecked[A] then
          AppDescriptions[A] := CustomMessage('BackupAppDesc')
        else
        begin
          AppDescriptions[A] := CustomMessage('BackupPartDesc');
          Log('Backup app left unchecked (installed by other programs): ' + ID);
        end;
        AppCount := AppCount + 1;
        BackupAppCount := BackupAppCount + 1;
      end;
    end;
    ApplyChanges(Changes);
    { Without extra apps the extra section stays out }
    if AppCount = CatalogCount then
      SectionCount := CatalogSectionCount;
    CurrentCat := CatBackup;
    Log('Backup apps: ' + IntToStr(BackupAppCount) + ' (' + IntToStr(AppCount - CatalogCount) + ' outside the catalog)');
  finally
    IDs.Free;
    Names.Free;
  end;
end;

{ ---------- Building the page ---------- }

function AddDetailLine(Band: TPanel; Line: Integer): TNewStaticText;
begin
  Result := TNewStaticText.Create(WizardForm);
  Result.Parent := Band;
  Result.AutoSize := False;
  Result.SetBounds(ScaleX(12), ScaleY(8) + Line * ScaleY(17), Band.Width - ScaleX(24), ScaleY(16));
  Result.Anchors := [akLeft, akTop, akRight];
end;

function AddToolButton(Page: TNewNotebookPage; Left, Width: Integer; const Caption: String): TNewButton;
begin
  Result := TNewButton.Create(WizardForm);
  Result.Parent := Page;
  Result.SetBounds(Left, 0, Width, ScaleY(23));
  Result.Anchors := [akTop, akRight];
  Result.Caption := Caption;
end;

procedure CreateAppPage;
var
  Page: TNewNotebookPage;
  W, H, Y, X, P, ButtonW, ComboW, Gap: Integer;
  Detail: TPanel;
begin
  Page := WizardForm.SelectComponentsPage;
  W := WizardForm.ComponentsList.Width;
  H := Page.Height;
  WizardForm.SelectComponentsLabel.Visible := False;
  WizardForm.TypesCombo.Visible := False;
  WizardForm.ComponentsList.Visible := False;
  { With no files to copy, this label would always say "0.0 MB". }
  WizardForm.ComponentsDiskSpaceLabel.Visible := False;

  { Toolbar: search, profiles, save and load }
  Gap := ScaleX(8);
  ButtonW := ScaleX(92);
  ComboW := ScaleX(176);
  SearchEdit := TNewEdit.Create(WizardForm);
  SearchEdit.Parent := Page;
  SearchEdit.SetBounds(0, 0, W - ComboW - 2 * ButtonW - 3 * Gap, ScaleY(23));
  SearchEdit.Anchors := [akLeft, akTop, akRight];
  SendTextMessage(SearchEdit.Handle, EM_SETCUEBANNER, 1, Msg('SearchCue', [IntToStr(CatalogCount)]));
  { The magnifier sits inside the box; the text starts to its right }
  SendMessage(SearchEdit.Handle, EM_SETMARGINS, EC_LEFTMARGIN, ScaleX(24));
  MakeMuted(CreateGlyph(SearchEdit, #$E721, 9, ScaleX(6), ScaleY(3)));
  SearchEdit.OnChange := @SearchEditChange;

  ProfileCombo := TNewComboBox.Create(WizardForm);
  ProfileCombo.Parent := Page;
  ProfileCombo.Style := csDropDownList;
  ProfileCombo.SetBounds(SearchEdit.Width + Gap, 0, ComboW, ScaleY(23));
  ProfileCombo.Anchors := [akTop, akRight];
  ProfileCombo.Items.Add(CustomMessage('ProfilePick'));
  for P := 0 to ProfileCount - 1 do
    ProfileCombo.Items.Add(ProfileName(P));
  ProfileCombo.ItemIndex := 0;
  ProfileCombo.OnChange := @ProfileComboChange;

  SaveButton := AddToolButton(Page, ProfileCombo.Left + ComboW + Gap, ButtonW, CustomMessage('SaveSelection'));
  SaveButton.OnClick := @SaveButtonClick;
  LoadButton := AddToolButton(Page, SaveButton.Left + ButtonW + Gap, ButtonW, CustomMessage('LoadSelection'));
  LoadButton.OnClick := @LoadButtonClick;

  Y := SearchEdit.Height + ScaleY(10);
  X := W * 31 div 100;

  SectionList := TNewCheckListBox.Create(WizardForm);
  SectionList.Parent := Page;
  SectionList.ShowLines := False;
  SectionList.MinItemHeight := ScaleY(22);
  SectionList.SetBounds(0, Y, X, H - Y);
  SectionList.Anchors := [akLeft, akTop, akBottom];
  SectionList.OnClick := @SectionListClick;

  AmdButton := TNewButton.Create(WizardForm);
  AmdButton.Parent := Page;
  AmdButton.SetBounds(0, H - ScaleY(26), X, ScaleY(26));
  AmdButton.Anchors := [akLeft, akBottom];
  AmdButton.Caption := CustomMessage('AmdButton');
  AmdButton.Visible := False;
  AmdButton.OnClick := @AmdButtonClick;

  X := X + ScaleX(12);
  ListTitle := TNewStaticText.Create(WizardForm);
  ListTitle.Parent := Page;
  ListTitle.AutoSize := False;
  ListTitle.Font.Size := 11;
  ListTitle.Font.Style := [fsBold];
  ListTitle.SetBounds(X, Y - ScaleY(4), W - X - ScaleX(170), ScaleY(21));
  ListTitle.Anchors := [akLeft, akTop, akRight];

  ListCount := TNewStaticText.Create(WizardForm);
  ListCount.Parent := Page;
  ListCount.AutoSize := False;
  ListCount.SetBounds(X, Y + ScaleY(18), W - X - ScaleX(170), ScaleY(16));
  ListCount.Anchors := [akLeft, akTop, akRight];
  MakeMuted(ListCount);

  ListLinks := TNewLinkLabel.Create(WizardForm);
  ListLinks.Parent := Page;
  ListLinks.AutoSize := False;
  ListLinks.Alignment := taRightJustify;
  ListLinks.UseVisualStyle := True;
  ListLinks.SetBounds(W - ScaleX(170), Y + ScaleY(17), ScaleX(170), ScaleY(18));
  ListLinks.Anchors := [akTop, akRight];
  ListLinks.Caption := '<a href="all">' + CustomMessage('SelectAll') + '</a>   ·   <a href="none">' +
    CustomMessage('SelectNone') + '</a>';
  ListLinks.OnLinkClick := @ListLinksClick;

  { Details: name and source, description, ID, why it is recommended and the note (two lines if needed) }
  Detail := CreateBand(Page, X, H - ScaleY(100), W - X, '');
  Detail.Height := ScaleY(100);
  Detail.Anchors := [akLeft, akRight, akBottom];
  DetailName := AddDetailLine(Detail, 0);
  DetailName.Font.Style := [fsBold];
  DetailName.AutoSize := True;
  DetailName.Anchors := [akLeft, akTop];
  DetailBadge := CreateColorPanel(Detail, ThemeColor('#005FB8', '#60CDFF'));
  DetailSource := TNewStaticText.Create(WizardForm);
  DetailSource.Parent := DetailBadge;
  DetailSource.Font.Size := 8;
  DetailSource.Left := ScaleX(7);
  DetailSource.Top := ScaleY(1);
  SetTextColor(DetailSource, '#FFFFFF', '#000000');
  DetailDesc := AddDetailLine(Detail, 1);
  DetailMeta := AddDetailLine(Detail, 2);
  MakeMuted(DetailMeta);
  DetailWhy := AddDetailLine(Detail, 3);
  MakeAccent(DetailWhy);
  DetailNote := AddDetailLine(Detail, 4);
  DetailNote.WordWrap := True;
  DetailNote.Height := ScaleY(32);

  AppList := TNewCheckListBox.Create(WizardForm);
  AppList.Parent := Page;
  AppList.ShowLines := False;
  AppList.MinItemHeight := ScaleY(22);
  AppList.SetBounds(X, Y + ScaleY(42), W - X, Detail.Top - ScaleY(8) - Y - ScaleY(42));
  AppList.Anchors := [akLeft, akTop, akRight, akBottom];
  AppList.OnClick := @AppListClick;
  AppList.OnClickCheck := @AppListClickCheck;

  { Total checked, left of the button bar; only visible on this page }
  FooterLabel := TNewStaticText.Create(WizardForm);
  FooterLabel.Parent := WizardForm;
  FooterLabel.AutoSize := False;
  FooterLabel.SetBounds(WizardForm.InnerNotebook.Left,
    WizardForm.NextButton.Top + (WizardForm.NextButton.Height - ScaleY(16)) div 2,
    WizardForm.BackButton.Left - WizardForm.InnerNotebook.Left - ScaleX(10), ScaleY(16));
  FooterLabel.Anchors := [akLeft, akBottom];
  FooterLabel.Visible := False;
end;

{ When the page is shown. The first time it detects the hardware. }
procedure ShowAppPage;
begin
  if not HardwareDetected then
  begin
    HardwareDetected := True;
    DetectHardware;
  end;
  FillSectionList;
  if HardwareText <> '' then
    WizardForm.PageDescriptionLabel.Caption := Msg('YourPc', [HardwareText])
  else
    WizardForm.PageDescriptionLabel.Caption := CustomMessage('AppsDescription');
  UpdateAppPage;
end;

{ ---------- What is going to be installed ---------- }

function AppIsSelected(AppIndex: Integer): Boolean;
begin
  { Exporting is the step before formatting: nothing is installed in that mode. }
  if BackupMode = BackupExport then
    Result := False
  else if AppComponents[AppIndex] = '' then
    Result := ExtraChecked[AppIndex]
  else
    Result := WizardIsComponentSelected(AppComponents[AppIndex]);
end;

function CountSelectedApplications: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to AppCount - 1 do
    if AppIsSelected(I) then
      Result := Result + 1;
end;

procedure BuildInstallQueue;
var
  I: Integer;
begin
  QueueCount := 0;
  for I := 0 to AppCount - 1 do
  begin
    if AppIsSelected(I) then
    begin
      InstallQueue[QueueCount] := I;
      QueueCount := QueueCount + 1;
    end;
  end;
end;
