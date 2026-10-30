#define MyAppName "ReinstallKit"
#define MyAppVersion "0.0.1"
#define MyAppPublisher "CASG-CRISTIAN"
; App catalog: its columns and how to save it are described in src\catalog.iss
#define CatalogPath AddBackslash(SourcePath) + "catalog_apps.csv"
; Windows tweaks of the options page: described in src\options_page.iss
#define TweaksPath AddBackslash(SourcePath) + "catalog_tweaks.csv"

[Setup]
AppId={{D7479A61-54DB-43C1-8207-05C2177A42B7}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppCopyright=Copyright (c) 2026 {#MyAppPublisher}. MIT License.
AppVerName={#MyAppName} {#MyAppVersion}
; Follows the Windows light or dark mode
WizardStyle=modern dynamic
; 17% larger than the stock window (120): the lists fit more rows
WizardSizePercent=140
WizardSmallImageFile=img\header.png
WizardSmallImageFileDynamicDark=img\header_dark.png
WizardImageFile=img\sidebar.png
WizardImageFileDynamicDark=img\sidebar_dark.png
CreateAppDir=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
; 64-bit mode: {sys} is the real System32 (pnputil.exe does not exist in SysWOW64).
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
DisableProgramGroupPage=yes
Uninstallable=no
OutputDir=output
OutputBaseFilename={#MyAppName}-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
SetupLogging=yes
CloseApplications=no
; Asks for the language at startup, suggesting the Windows one. It applies to the wizard, the log and
; the apps that let you choose one; /LANG=spanish, /LANG=english or /LANG=french skips the question.
ShowLanguageDialog=yes

[Languages]
; Inno's own texts first, then the program's
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl,lang\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl,lang\English.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl,lang\French.isl"

[Files]
; PowerShell scripts and WinUtil's tweak definitions: the code extracts them to {tmp} when it needs them
; (ExtractTemporaryFile), nothing is copied to the PC. WinUtil's license goes along with its file.
Source: "scripts\*"; DestDir: "{tmp}"; Flags: dontcopy

; Modules in dependency order: each one only uses what the previous ones define.
#include "src\common.iss"
#include "src\catalog.iss"
#include "src\theme.iss"
#include "src\dialogs.iss"
#include "src\hardware.iss"
#include "src\backup_page.iss"
#include "src\apps_page.iss"
#include "src\options_page.iss"
#include "src\install_page.iss"
#include "src\tools.iss"
#include "src\backup.iss"
#include "src\tweaks.iss"
#include "src\winget.iss"
#include "src\parallel.iss"
#include "src\report.iss"
#include "src\usb_restart.iss"
#include "src\installation.iss"
#include "src\ready_page.iss"
#include "src\wizard.iss"
