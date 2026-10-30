[Types]
Name: "custom"; Description: "{cm:CustomType}"; Flags: iscustom

; ---------------------------------------------------------------------------
; App catalog, generated at compile time from catalog_apps.csv (CatalogPath).
; Save it from Excel as "CSV (delimitado por comas)": ';' separator and ANSI encoding
; (Inno's preprocessor cannot read UTF-8). Columns, counting from 0:
;    0 Section_ES    1 Component      2 Name_ES          3 Description_ES   4 WingetID
;    5 Source        6 Included       7 AsUser           8 Note_ES
;    9 Section_EN   10 Name_EN       11 Description_EN  12 Note_EN         13 WingetID_EN
;   14 Section_FR   15 Name_FR       16 Description_FR  17 Note_FR         18 WingetID_FR
;   19 Profiles (space-separated: basic gaming office dev)
;   20 OtherIDs (space-separated: other packages of the same app, so a backup that has one of them
;      ticks this app instead of adding a second copy; e.g. MSI Center from WinGet and from the Store)
; The base columns are Spanish. The _EN and _FR ones are used with the wizard in English or
; French; when empty, French falls back to English and English to Spanish (see Pick).
; ---------------------------------------------------------------------------
#define CsvHandle 0
#define CsvLine ""
#define LastGroup ""
#define LastSection ""
#define AppTotal 0

; Field N (from 0) of a ';'-separated line; empty if the line has fewer fields
#define Field(str S, int N) N == 0 ? Trim(Pos(";", S) ? Copy(S, 1, Pos(";", S) - 1) : S) : (Pos(";", S) ? Field(Copy(S, Pos(";", S) + 1), N - 1) : "")
#define IsYes(str S) SameText(S, "Yes") || SameText(S, "Si") || SameText(S, "Sí")
#define GroupOf(str C) Copy(C, 1, Pos("\", C) - 1)
; Field N of the current line as a Pascal string literal: quoted, with its single quotes doubled
#define Q(int N) "'" + StringChange(Field(CsvLine, N), "'", "''") + "'"
; The same text in the three languages, for Pick
#define Langs(int Es, int En, int Fr) Q(Es) + ", " + Q(En) + ", " + Q(Fr)

#sub EmitComponent
  #expr CsvLine = Trim(FileRead(CsvHandle))
  #if Pos("Ã", CsvLine)
    #error catalog_apps.csv is saved as UTF-8: save it from Excel as "CSV (delimitado por comas)" so accented letters survive
  #endif
  #if CsvLine != "" && IsYes(Field(CsvLine, 6))
    #if GroupOf(Field(CsvLine, 1)) != LastGroup
      #expr LastGroup = GroupOf(Field(CsvLine, 1))
Name: "{#LastGroup}"; Description: "{#Field(CsvLine, 0)}"
    #endif
Name: "{#Field(CsvLine, 1)}"; Description: "{#Field(CsvLine, 2)}"
    #expr AppTotal = AppTotal + 1
  #endif
#endsub

; A new section whenever the Section_ES column changes; texts are emitted in every language and Pick
; chooses at run time. Every language's ID goes along too, to recognise the app in a backup.
#sub EmitAddApp
  #expr CsvLine = Trim(FileRead(CsvHandle))
  #if CsvLine != "" && IsYes(Field(CsvLine, 6))
    #if Field(CsvLine, 0) != LastSection
      #expr LastSection = Field(CsvLine, 0)
  NewSection(Pick({#Langs(0, 9, 14)}));
    #endif
  AddApp({#Q(1)}, {#Field(CsvLine, 5) == "" ? "'winget'" : Q(5)}, {#IsYes(Field(CsvLine, 7)) ? "True" : "False"},
    Pick({#Langs(2, 10, 15)}), Pick({#Langs(3, 11, 16)}), Pick({#Langs(4, 13, 18)}), Pick({#Langs(8, 12, 17)}),
    '|' + {#Q(4)} + '|' + {#Q(13)} + '|' + {#Q(18)} + '|' + {#StringChange(Q(20), " ", "|")} + '|', {#Q(19)});
  #endif
#endsub

[Components]
; No component belongs to a type, so the list starts unchecked. This Inno list stays hidden and only
; stores the selection (see apps_page.iss): its descriptions are never shown.
#expr CsvHandle = FileOpen(CatalogPath)
#if !CsvHandle
  #error Cannot open catalog_apps.csv
#endif
#expr FileRead(CsvHandle)
#for {0; !FileEof(CsvHandle); 0} EmitComponent
#expr FileClose(CsvHandle)
#if AppTotal == 0
  #error catalog_apps.csv has no app with Included=Yes
#endif

[Code]
{ ---------- Catalog: the apps from the CSV, in the chosen language ---------- }

const
  { The catalog plus room for the apps of a backup that are not in it (see apps_page.iss).
    A fixed margin: extra apps beyond it are left out and logged. }
  MaxApps = {#AppTotal + 200};

var
  AppCount: Integer;
  CatalogCount: Integer;          { apps from the CSV; the ones after them come from a backup }
  CatalogSectionCount: Integer;
  AppComponents: array[0..MaxApps - 1] of String;  { empty for apps from a backup }
  AppSources: array[0..MaxApps - 1] of String;
  AppAsUser: array[0..MaxApps - 1] of Boolean;
  AppNames: array[0..MaxApps - 1] of String;
  AppDescriptions: array[0..MaxApps - 1] of String;
  AppPackageIDs: array[0..MaxApps - 1] of String;
  AppNotes: array[0..MaxApps - 1] of String;
  AppSection: array[0..MaxApps - 1] of Integer;
  AppAllIDs: array[0..MaxApps - 1] of String;      { '|id|id_en|id_fr|' in lowercase }
  AppProfiles: array[0..MaxApps - 1] of String;    { ' basic gaming ' }
  SectionCount: Integer;
  SectionNames: array[0..MaxApps - 1] of String;

{ The CSV column for the chosen language. An empty column falls back: French to English, English to
  Spanish (the base column is never empty). }
function Pick(const Es, En, Fr: String): String;
begin
  Result := Es;
  if (ActiveLanguage <> 'spanish') and (En <> '') then
    Result := En;
  if (ActiveLanguage = 'french') and (Fr <> '') then
    Result := Fr;
end;

procedure NewSection(const Name: String);
begin
  SectionNames[SectionCount] := Name;
  SectionCount := SectionCount + 1;
end;

{ Goes into the last section created: the rows of a section are consecutive in the CSV }
procedure AddApp(const ComponentName, SourceName: String; AsUser: Boolean;
  const DisplayName, Description, PackageID, Note, AllIDs, Profiles: String);
begin
  AppComponents[AppCount] := ComponentName;
  AppSources[AppCount] := SourceName;
  AppAsUser[AppCount] := AsUser;
  AppNames[AppCount] := DisplayName;
  AppDescriptions[AppCount] := Description;
  AppPackageIDs[AppCount] := PackageID;
  AppNotes[AppCount] := Note;
  AppAllIDs[AppCount] := Lowercase(AllIDs);
  AppProfiles[AppCount] := ' ' + Profiles + ' ';
  AppSection[AppCount] := SectionCount - 1;
  AppCount := AppCount + 1;
end;

procedure InitializeApplicationCatalog;
begin
  AppCount := 0;
  SectionCount := 0;
  { Generated from catalog_apps.csv }
#expr CsvHandle = FileOpen(CatalogPath)
#expr FileRead(CsvHandle)
#expr LastSection = ""
#for {0; !FileEof(CsvHandle); 0} EmitAddApp
#expr FileClose(CsvHandle)
  CatalogCount := AppCount;
  CatalogSectionCount := SectionCount;
end;
