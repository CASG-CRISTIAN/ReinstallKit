# ReinstallKit — v0.0.1

An installer built with Inno Setup that puts a freshly formatted Windows back the way it was:
- it saves and restores the drivers, the Wi-Fi networks and the list of apps;
- it reinstalls your apps with WinGet;
- it applies WinUtil's Windows settings.

It is free software, under the [MIT](LICENSE) license.

## Typical use

0. **When it opens**, it asks for the language and suggests the Windows one: Spanish, English or French. See [Language](#language).
1. **Before formatting:** run the installer and choose **Save a backup of this PC**. Save it to a USB drive or another disk you are not going to wipe. By default it uses the folder `Drivers_<PC-NAME>` next to the installer.
2. **After reinstalling Windows:** run the installer from the same USB drive and choose **Restore a backup**. It suggests the `Drivers_*` folder next to the installer and ticks the apps you had.
3. **Review** the apps and the Windows settings, and click **Install**.
4. **When it finishes**, the log opens so you can review it. When you click **Next**, the wizard asks whether you want to restart; if you say yes, it closes and restarts the PC. After saving a backup, it offers instead to restart into the Windows installation USB (see [Restarting into the Windows installation USB](#restarting-into-the-windows-installation-usb)).

Without a backup, choose **Don't use a backup**: you go straight to the apps and the settings.

## Language

Before starting, the installer asks for the language and suggests the Windows one. That language is used for:

- **The wizard, the messages and the log** on the Desktop. The log is called `Registro ReinstallKit <date>.txt` in Spanish, `ReinstallKit log <date>.txt` in English and `Journal ReinstallKit <date>.txt` in French.
- **The apps that let you choose it:**
  - **Firefox, Firefox Developer Edition and Thunderbird:** Mozilla publishes one package per language: `Mozilla.Firefox.es-ES`, `Mozilla.Firefox` (English) and `Mozilla.Firefox.fr`. The catalog's `WingetID_EN` and `WingetID_FR` columns decide which.
  - **Battle.net:** its installer gets the language in `--lang` (`esES`, `enUS` or `frFR`).
- **Every other app** uses the Windows language by itself, so it is not told anything. This was checked with `winget show --locale`: the catalog has no other packages with per-language installers, and asking for one that does not exist makes the installation fail.

`/LANG=spanish`, `/LANG=english` or `/LANG=french` skips the question. In silent mode nothing is asked: the Windows language is used, or the one given in `/LANG`.

## The backup

**Save a backup of this PC** creates the folder `Drivers_<PC-NAME>` with:

| What | How | Where |
|---|---|---|
| The manufacturers' drivers | `pnputil /export-driver *` | One subfolder per driver |
| Wi-Fi networks, with their passwords (optional) | `netsh wlan export profile key=clear` | `wifi\` |
| List of apps (optional) | `winget export` | `apps.json`, plus the names of the Microsoft Store apps in `apps_names.txt` |
| Catalog apps that WinGet does not recognize | By their name | `apps_by_name.txt` |

The Wi-Fi passwords are readable in the backup: keep it somewhere you trust. The backup does not include your files.

**Apps that WinGet does not recognize.** `winget export` only lists what it can match to a package, and warns about the rest with *"Installed package is not available from any source: …"*. Most of those are Windows components, drivers, games from other launchers or parts of other programs. But catalog apps installed some other way show up too: Firefox in Spanish, Spotify from the Store, Discord… WinGet installs them all the same; it just does not recognize the copy you already have.
- **When saving,** the installer compares those names with the catalog by their base name, without what changes from one installation to another: from ` (`, `:` or a version number on. *Mozilla Firefox (x64 es-ES)* becomes `Mozilla Firefox`, and *Spotify: música y pódcasts*, `Spotify`.
- It only counts if it matches **one** catalog app. For example, *Visual C++ 2013 UWP* matches two and is discarded.
- The matches are saved in `apps_by_name.txt`, so the `apps.json` that `winget import` reads is left untouched. The task says which ones they were.
- **When restoring,** they come out ticked, just like those in the list.

netsh silently truncates any profile path longer than 127 characters and writes the file somewhere else. That is why it exports and adds the networks through a short folder of the installer's own (the 8.3 form of its temporary folder, private to your user) and copies them from or to the backup. The temporary files, which hold the passwords, are deleted right away. If netsh says it saved more networks than reach the backup, the task ends with *Warning*.

If you choose to save it on the same drive as Windows, the wizard asks you to confirm, because formatting would wipe it.

**The folder cannot be too deep.** Windows does not accept paths longer than 260 characters, and neither pnputil nor DISM can get around that limit. Each driver is saved in a subfolder named as in the driver store (`hdx_msiext_avo_v4_cap_dsp_intgo_win11.inf_amd64_<hash>\…`), and in a deep folder the long-named ones do not fit: pnputil says *"The data is invalid"* and DISM says *"Error: 206"*.
- **When you click Next** on the folder page, the wizard measures the longest path the backup will need. It measures all of `C:\Windows\System32\DriverStore\FileRepository`, Windows' own drivers included, to err on the safe side. If it does not fit, it will not go on: it says how many characters the folder may have and offers the root of the same drive (for example, `E:\Drivers_<PC-NAME>`).
- **When restoring,** it measures the paths of the chosen backup. If any is longer than 260 (for example, because it was moved with a tool that does handle long paths), it asks you to move it somewhere shorter.
- From the root of a USB drive, which is the usual case, there is plenty of room: on a PC with 524 drivers the longest path is about 150 characters.

**If the drivers cannot be saved:**
1. If pnputil fails, or saves fewer than there are, it tries again with **DISM** (`dism /online /export-driver`). DISM is Windows' other tool for this and does it with its own code. It saves to the `dism` subfolder, without overwriting what pnputil did save; restoring reads every subfolder.
2. If DISM fails too, the task ends with *Warning* and both error codes. If the cause is the path length, the advice says so and suggests a shorter folder. Otherwise it includes the free space left on the backup's drive: a full, unplugged or antivirus-blocked USB drive are the usual causes.
3. When you click **Next**, instead of offering to restart, a message says **"The backup isn't complete: don't format yet"**, with what failed. You can close without restarting or go on anyway: for example, if only the list of apps failed.

### Restarting into the Windows installation USB

If the backup finishes without warnings, clicking **Next** offers to restart and install Windows from the USB drive, without having to press F12 or Del at just the right moment. First it checks the PC and reports what it found:

| It checks | How |
|---|---|
| Whether it boots in UEFI or legacy BIOS mode | Windows' `GetFirmwareType` |
| Whether Secure Boot is on | The registry (`SecureBoot\State`) |
| Whether the recovery environment is there, which is what offers "Use a device" | `C:\Windows\System32\Recovery\ReAgent.xml` |
| Whether a Windows installation USB drive is plugged in | A drive with `\efi\boot\bootx64.efi` and `\sources\install.wim` (or `.esd`) |

The window comes in parts, so it can be read at a glance:
1. **What it found,** in a band, one line per item: ✓ in green if it is fine, ⚠ in orange if something needs doing, ℹ in blue if it is just information. The USB drive comes first, because without it there is nothing to boot.
2. **"How do you want to restart?",** with one option for each possible way. The recommended one says *(recommended)* and is selected, and each one says below what to do after the restart.
3. **"Show more details"** expands the technical part: the exact command of each option, Secure Boot, why "Use a device" is missing when Windows recovery is off, and how to cancel the restart.
4. **Restart** or **Don't restart now.**

The options, depending on what it finds:

| Option | Command | When |
|---|---|---|
| Advanced startup | `shutdown /r /o /t 10` | **Recommended** on UEFI. After the restart, choose **Use a device** and your USB drive. The BIOS can also be reached from that same menu. |
| BIOS/UEFI | `shutdown /r /fw /t 10` | The alternative on UEFI, or the recommended one if the recovery environment is off. Choose the USB drive in the BIOS boot menu. |
| Plain restart | `shutdown /r /t 10` | On legacy BIOS, where Windows cannot choose the boot device: press the boot menu key (usually F12, F11, F8 or Esc). |

- The PC restarts after 10 seconds and Windows closes the open programs. `shutdown /a` cancels it in the meantime.
- If Windows rejects an option (for example, firmware that does not support `/fw`), the message says so with its code and offers the others again.
- If it does not find the USB drive, it tells you to plug it in before restarting.
- With Secure Boot on, the USB drive has to be an official one: made with Microsoft's Media Creation Tool, or with Rufus and the original image.

**Restore a backup** does this, in this order (on the folder page, two boxes ticked by default decide whether the drivers and the Wi-Fi networks are restored):

1. It installs the drivers: `pnputil /add-driver <folder>\*.inf /subdirs /install`. Then it shows which devices work now (see [How to tell it went well](#how-to-tell-it-went-well)).
2. It adds the Wi-Fi networks: `netsh wlan add profile ... user=all`. Windows connects by itself and the installer waits up to 20 s for the Internet. If the Windows Wi-Fi service does not start (there is no adapter, or it lacks its driver), it says so in one line and the networks stay in the backup.
3. It ticks the backup's apps in the list:
   - those in the catalog are ticked in their section;
   - the others appear in **Others from your backup**;
   - the **From your backup** category gathers them all.

   The components Windows installs by itself (UI.Xaml, VCLibs, App Installer...) are not ticked. The add-ons that another program installed (older Visual C++, .NET Runtime, SQL Server ODBC and OLE DB drivers, PhysX, GameInput, Epic Online Services, Python Launcher) come out **unticked**: the program that needs them installs them again. They are listed in `BackupPartPrefixes`, in `src\apps_page.iss`.

The drivers and the Wi-Fi go before the apps: if the network driver was missing, WinGet is online by then.

## Choosing the apps

- **On the left**, the categories, each with a counter (*2/5* = 2 of 5 ticked):
  - **From your backup**, if you restore one;
  - **Recommended for you**, based on your hardware;
  - **All**;
  - and the catalog's sections.
- **On the right**, the list of the chosen category. **Select all** and **None** only affect what that list shows.
- **The search box** filters the whole catalog by name or section, ignoring case and accents.
- **Select a profile…** ticks a typical set at once:

  | Profile | Apps |
  |---|---|
  | Basic | Visual C++, DirectX and .NET, Chrome, Acrobat Reader, VLC and 7-Zip |
  | Gaming | Visual C++, DirectX and .NET, Steam, Epic Games, Discord, HWMonitor, RivaTuner and OBS Studio |
  | Office | Chrome, Acrobat Reader, Thunderbird, LibreOffice, Teams, Zoom, KeePass and 7-Zip |
  | Programming | Notepad++, Python, VS Code, Windows Terminal, Git, SQLite, Postman, 7-Zip and PowerToys |

  The profiles come from the catalog's `Profiles` column.
- **Save…** and **Load…** save your selection to an `.inf` file and bring it back another time. It is the same format as Inno Setup's `/SAVEINF` and `/LOADINF`.
- **The panel below** shows the selected app:
  - its name, with a tag saying where it is installed from (**WinGet** or **Microsoft Store**);
  - a short description;
  - its ID, and whether it installs as administrator or as a standard user;
  - why it is recommended, and the note from the CSV.
- The bottom left shows how many you have ticked in total.

## Windows settings

The **Settings and options** page, before installing, gathers what is done besides the apps:

- **Suggestions for this PC**, only when they apply. For now there is one: if there is another internal disk or partition with at least 20 GB free, it offers to **keep Documents, Downloads, Pictures, Videos and Music on it** (the one with the most free space; USB drives, SD cards and virtual disks do not count). It comes unticked.
  - They go to `<drive>:\<your user name>\Documents`, `\Downloads`… Off the Windows drive, they take no room there and survive a reformat.
  - If that folder already exists (from before formatting), it is used as it is, with whatever it holds. Otherwise it is created private to you, like your user folder.
  - What the current folders hold is not moved: right after formatting they are empty, and the installer and the backup may be in Downloads. The task says how many items are left in each.
  - It does the same as each folder's *Properties → Location → Move* (`scripts\move_user_folders.ps1`) and shows after a restart. *Properties → Location → Restore Default* undoes it.
- **Installing the apps:** one at a time, or 2, 3 or 4 at a time (see [Several at a time](#several-at-a-time)). What suits your PC comes selected:
  - 3 with 8 logical processors and 16 GB of RAM;
  - 2 with 4 and 8 GB;
  - otherwise one at a time, and also in a virtual machine, which shares its disk, network and processors with the PC that runs it.
- **Before starting:** create a restore point. It comes unticked: tick it if you want to be able to undo everything with *System Restore*.
  - If *System Protection* is off (it usually is on a fresh Windows 11), ticking it **asks** whether you want to turn it on, because without it there is no restore point. If you say no, it is unticked. It asks at that moment, not halfway through the installation, so that the installation can run unattended.
  - If the installer turns it on, it limits it to **5 %** of the disk (`vssadmin Resize ShadowStorage /For=C: /On=C: /MaxSize=5%`) and leaves it on. The task and the log say how to turn it off once you see that everything is fine: `Disable-ComputerRestore -Drive 'C:\'`, or *System Protection → Configure → Disable system protection*. Turning it off deletes the restore points.
  - If it was already on, its configuration is left alone. If the restore point is not created after all, it is turned off again.
  - Whether it is on is known because Windows records the protected drives in `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SPP\Clients`, read the same way Microsoft's `ComputerManagementDsc` module does.
- **The Windows settings**, in three groups. They come from [WinUtil](https://github.com/ChrisTitusTech/winutil), by Chris Titus Tech (MIT license):

  | Group | What is in it | Ticked by default |
  |---|---|---|
  | **Essentials** | Privacy and performance: telemetry, activity history, location, services, ads, temporary files... | WinUtil's *Standard* selection, plus this installer's usual ones |
  | **Preferences** | How Windows looks and behaves: file extensions, dark mode, taskbar, mouse, keyboard... | Only *Show file extensions* |
  | **Advanced** | Only advisable if you know what you are doing: removing Edge or OneDrive, IPv6, visual effects, power plan... | None |
- **When finished:** update everything already installed with WinGet (`winget upgrade --all`).

Click any row to see below what it does. Settings that only exist on Windows 11 do not appear on Windows 10.

### How they are applied

Each setting is an entry of `scripts\winutil_tweaks.json`, WinUtil's file as it is, or of `scripts\custom_tweaks.json`, ours in the same format. It may include:
- registry values;
- services;
- scheduled tasks;
- PowerShell scripts.

`scripts\apply_tweaks.ps1` applies them the way WinUtil does, with one administrator PowerShell per setting:
- each one shows what it changes in its task;
- if one fails, the rest go on;
- the summary names the ones that could not be applied, with their first error, for example *Uninstall OneDrive (Access to the path 'adal.dll' is denied.)*.

Some changes show after restarting or signing in again.

Details:
- WinUtil's *toggles* (turning something on or off) are offered in the direction opposite to Windows' defaults. For example, *Disable mouse acceleration* applies WinUtil's `-Undo`. The CSV's `Undo` column marks them.
- If the installer is elevated with another administrator account, the user settings (`HKCU`) are still written to the session of whoever is in front of the PC.
- WinUtil sometimes restarts Explorer; this installer does not, so the taskbar does not flicker halfway through the installation. The exceptions are the classic context menu and uninstalling OneDrive, whose scripts restart it.
- If you tick *Uninstall OneDrive* and OneDrive is also among the apps (almost any backup has it, because Windows comes with it), clicking Next **asks** which of the two you want: the settings go before the apps, so with both it would be removed and installed again. *Remove OneDrive* unticks the app, and the *Ready to go* page says so; *Keep OneDrive* unticks the setting.

**To undo** a single one, run in an administrator console:

```
powershell -ExecutionPolicy Bypass -File scripts\apply_tweaks.ps1 -Id <Id> -Undo
```

If its row has `Undo=Yes`, run it without `-Undo`. With `-DryRun` it only shows what it would do.

### What was not taken from WinUtil

| WinUtil setting | Why |
|---|---|
| Restore point | Already in *Before starting* |
| Bing search | *Remove web search (Bing) from the Start menu* does the same and also sets the policy that newer Windows 11 versions honor |
| Delete temporary files | Replaced by an identical one that does not delete the installer's own folder |
| Multiplane Overlay | It is a drop-down; its compatibility mode is offered as *Disable Multiplane Overlay (MPO)* |
| Ultimate Performance power plan | It is two buttons; turning it on is offered, without the one that removes it |
| Disk cleanup | It takes a long time, and right after formatting there is nothing to clean |
| O&O ShutUp10++ | It opens a program to be used by hand |
| DNS | A provider has to be chosen; still pending |
| Store results in the Start menu search | It locks a file of the Store itself (`store.db`), and WinGet installs the Store apps through the Store |

`tools\check_tweaks.ps1` rejects any setting that removes or disables the Store or App Installer (WinGet), touches their files, disables the services they install with, or removes the `msstore` source.

## Appearance

- The wizard follows **Windows' light or dark mode** (`WizardStyle=modern dynamic`, from Inno Setup 6.6), its messages included.
- Every page shares one style: a soft-colored band with an icon for explanations, native Windows lists, and messages whose buttons say what they do.
- **The window can be enlarged** by dragging its border or with the maximize button (`WizardResizable`, on by default with the modern style): the lists and bands grow with it, because each control says how with its `Anchors`. It cannot be made smaller than its opening size.
- **Every message and question window is the same one** (`src\dialogs.iss`), the one for quitting the installer included.
  - They take 70 % of the wizard's width, because the standard Windows box is narrow, cannot be widened, and cut long titles in dark mode.
  - The title sits next to an icon for its kind: a red ✕ for an error, an orange ⚠ for a warning, a blue ? for a question and a blue ℹ for information.
  - The buttons are normal-sized and sit in one row; if they do not fit, they stack. The first one answers to Enter and the last one to Esc.
  - When there is a lot to read, the explanation waits behind **Show more details**. That happens, for example, with the reason for the Store certificate error, or with the per-app summary at the end.
- The images are in `img\`: `header.png` (header) and `sidebar.png` (final page), each with a `_dark` version for dark mode. They are PNGs with transparency; if you replace them, keep the aspect ratio.

## During the installation

- Each task is a row with its state on the right: *Pending*, *Installing…*, *Installed*, *Already installed*, *Error*… The restore point, the backup, the settings and each app are tasks.
- **Click a row to expand it (+) or collapse it (−)** and see everything it did:
  - the package or the folder;
  - the output of WinGet, pnputil or PowerShell;
  - the result, with how long it took.

  Expanded rows update live.
- The top shows what it is doing and **for how long**, for any task. For example:
  - *Restoring the drivers... 37 of 524 (0:45)*, with the line pnputil has just written below it;
  - *Setting 3 of 12: Disable telemetry*.

  That way you know it has not hung.
- **When something fails, a notice appears** over the list with the reason and the advice:
  - it does not stop the installation;
  - it closes by itself after 10 s;
  - **Pause** keeps it there to read calmly, and **Close** moves on to the next one;
  - if several things fail in a row, they wait in a queue and the notice says how many are left;
  - what you skip yourself gives no notice;
  - a paused notice does not hold anything up: the installation finishes all the same, and the notice stays until you close it or leave the page.
- **Each failure also sends a Windows notification**, and at the end another one arrives with the result and the list of what failed; clicking that last one opens the log. Windows may stack the failure ones under the last one, which is why the final one repeats the names. Windows removes them by itself after 3 days. If you leave the installer working, the Notification Center keeps the list of what failed.
  - They are sent in the installer's name, which it registers in `HKCU\Software\Classes\AppUserModelId\ReinstallKit`. That is what Windows needs for a program that does not come from the Store.
  - When it closes, the installer deletes that key and the two that Windows creates by itself the first time an app sends a notification (`...\CurrentVersion\Notifications\Settings\ReinstallKit` and `...\CurrentVersion\PushNotifications\Backup\ReinstallKit`, under `HKCU\Software\Microsoft\Windows`). It does so on Finish, on Cancel and also before a restart, the restart into the USB drive after saving a backup included.
  - `scripts\toast.ps1` sends them as your user, not as administrator, because the Notification Center is yours.
  - If *Do not disturb* is on, Windows does not show them at the moment, but keeps them all the same.
  - In silent mode none are sent.
- The window does not freeze: you can expand rows, scroll the list or **Cancel** at any time.
  - Cancel **cuts the app being installed at once**, as Skip does, and leaves the rest unprocessed. That app may be left half installed: the log says so and gives the command to reinstall it.
  - A backup or settings step is not cut, so as not to leave Windows half changed: the queue stops when it ends.
- **Without an Internet connection**, a message appears before installing the apps:
  - it offers two choices: **Retry** (for example, after connecting to the Wi-Fi) or **Cancel the installation**;
  - there is no way to go on, because every app is downloaded from the Internet;
  - it is checked after restoring the drivers and the Wi-Fi;
  - the connection counts if WinGet's CDN or Windows' own connectivity check answers.
- The apps are installed one at a time or **several at a time**, as chosen on the settings page (see [Several at a time](#several-at-a-time)).
- If an installer gets stuck waiting for an answer, **Skip this app** cuts it and goes on with the next one. After **10 minutes** it is skipped automatically (`AppTimeoutMinutes` in `src\install_page.iss`).

## Log

When it finishes, a report with the date and time is saved to your **Desktop** and opens automatically. It is written in the chosen language and meant to be read from top to bottom:

1. **Header:** PC, hardware, start and end time, duration and result.
2. **SUMMARY:** the requested apps, grouped by reason, and one line per step (backup, settings, updates):
   ```
   Of 12 apps requested:
     • Installed now: 7
     • Already installed: 3
         2 · up to date
         1 · not updated because it was open
     • Not installed: 2
         1 · its ID doesn't exist in WinGet
         1 · skipped: still running after 10 min
   Windows settings: 12 applied
   ```
3. **TO REVIEW:** only if something failed or was skipped. For each task it gives:
   - the reason;
   - advice, given only once even when several tasks share it;
   - the command to retry it by hand (`winget install --id … -e`).
4. **RESULT BY TASK:** a table with the state of each task.
5. **DETAILS OF EACH TASK:** the same you see when expanding the rows.

If Setup were cut short, what happened up to that moment is in Inno's internal log (`%TEMP%\Setup Log <date>.txt`). When Setup closes normally, it deletes that log, because the Desktop report already holds it all. To keep it, run the installer with `/LOG="C:\path\log.txt"`.

## Drivers

- **Saving** copies every manufacturer driver in the Windows driver store: graphics, sound, chipset, network, printers…
- **Restoring** adds every driver to the store and installs those that match the hardware present. If any fails, the task ends with *Warning* and the details appear in the log.
- Before starting, it counts how many there are:
  - when saving, Windows' `oem*.inf` files;
  - when restoring, the backup's `.inf` files.

  pnputil writes a line as it starts each driver; that is where the *37 of 524* counter comes from.
- pnputil writes in the ANSI code page. `scripts\stream_ansi.ps1` converts each line to UTF-8 as soon as it arrives, so it shows live and with its accents.
- What is **not** copied:
  - the drivers Windows already ships with;
  - each manufacturer's control panel (NVIDIA App, AMD Adrenalin, Realtek Audio Console…). Those are apps; several are in the catalog.

### How to tell it went well

- **When saving**, the result says how many were saved out of how many there were: *524 of 524 saved to…*. If any is missing, the task ends with *Warning*. The figures come from the summary pnputil ends with.
- **When restoring**, the result says how many were added to Windows (*520 of 524 added to Windows*).
- **It also compares the devices with problems before and after.** Those are the ones Device Manager marks with a yellow triangle.
  - When you expand the drivers task, the very top says how many there were, which ones **work now** and which ones are **still without a driver**.
  - If any is left, the task ends with *Warning* and the log explains what to do.
  - At the end, the **View devices** button appears; it opens Device Manager.
- **To count them by hand**, count the drivers added to Windows. In a console, `pnputil /enum-drivers` lists them (one entry per `oem*.inf`), and that is what goes into the backup.
  - `driverquery` or the services are no good for comparing: they include some 380 drivers that come with Windows itself, and only those for the hardware the PC has.
  - That is also why, in a virtual machine, another PC's backup gets added, but almost nothing gets installed: that hardware is missing.

## Apps

- They are installed with `winget install --id <ID> -e --silent`, one at a time or several at a time (see [Several at a time](#several-at-a-time)).
- If the app was already installed, it does not count as an error but as **Already installed**. There are three cases:
  - up to date;
  - with another version, which is left as it was;
  - not updated because it was open (Discord, Steam or Teams in the background).

  That happens with Edge, with Windows Terminal on Windows 11 and with everything you already have when running the installer again.
- It retries twice, waiting 30 s, in two cases:
  - another installation is in progress (Windows Update, for example);
  - WinGet is not ready yet: right after formatting, the Store updates App Installer in the background and, meanwhile, `winget.exe` may not start or may not open its sources (0x80071130).
- **If it fails for something that may be passing, it gets one more try at the end**, after the others. That happens when its installer ends with an error (0x8A150006), the download or a dependency fails, another installation is in progress or WinGet is not ready. The failure may come from something another installer was using at that moment.
  - Until then its row says *Will retry* and gives no notice.
  - What is not going to change is not retried: an ID that does not exist, an incompatible package, a policy, a full disk, or NVIDIA App without an NVIDIA graphics card.
- If WinGet is not registered yet (it happens in the first minutes of a fresh Windows), the installer registers it with the command Microsoft documents.
- Mozilla's products and Battle.net are installed in the chosen language; the rest take the Windows one (see [Language](#language)).
- **Battle.net** requires an installation folder: without one, WinGet stops to ask for it.
  - That is why it gets `--location "C:\Program Files (x86)\Battle.net"`.
  - For the language it gets its own arguments with `--override` (`--lang=esES --installpath=…`), because its manifest already passes `--lang=enUS`.
  - It is in `src\winget.iss`.
  - Its installer has no silent mode, so it may show its own window while it works. If it gets stuck waiting, **Skip this app** does the job.

### Several at a time

With 2, 3 or 4 at a time (settings page), the apps finish sooner: while one installs, others download.
- Only the WinGet apps that install as administrator run in parallel. The Microsoft Store apps and those that install as a standard user go afterwards, one at a time: the Store has its own queue, and its certificate check may need a question.
- `scripts\install_parallel.ps1` launches the `winget install` commands and passes on each one's output tagged with its number; the wizard sorts it into their tasks, which show in bold while they work.
- The status line says how many are running at a time and how many are done, and names the one running longest, with its time. **Skip this app** skips that one, and only that one: it cuts its `winget` by its process ID (`taskkill /PID … /T`). The 10-minute limit applies to each one.
- Windows Installer only allows one MSI installation at a time. If two clash, WinGet returns *installation in progress* (0x8A150102) and the one that could not run is retried after 30 s, up to three times. If it still fails, it goes into the final retry, which is one at a time.
- **Cancel** cuts all those running and starts no more.
- In silent mode they are installed one at a time, because the settings page options are not applied.

### Error 0x8A15005E with Microsoft Store apps

*"The server certificate did not match any of the expected values"*. WinGet checks the Microsoft Store certificate against a list that **App Installer** carries. It fails in two cases (see [winget-cli#2879](https://github.com/microsoft/winget-cli/issues/2879)):

- **App Installer is old** and its list is out of date. It happens a lot right after formatting.
  - On the first error, the installer updates it once from the `winget` source (`winget upgrade --id Microsoft.AppInstaller`) and retries that app.
  - If that fixes it, the following Store apps install normally.
- **An antivirus, proxy, firewall or VPN inspects HTTPS connections** and replaces the certificate.
  - If it still fails after the update, the installer **asks once** whether WinGet may check the Store the way Windows does, only while the installation lasts. It is the official `BypassCertificatePinningForMicrosoftStore` setting.
  - The connection is still encrypted and verified by Windows; only WinGet's own list is dropped, which the Microsoft Store app does not use either.
  - If you agree, it retries, and at the end (also if you cancel) the check is turned back on: the setting goes back to its default (`winget settings reset`), as if it had never been touched.
  - If you do not agree, or in silent mode, those apps are left uninstalled and the log explains what to do.

`winget source reset` does not fix it.

Other ways to get the Store apps, without downloading anything by hand:
- **The hardware apps** (NVIDIA Control Panel, Intel Graphics Command Center, Realtek Audio Console, Thunderbolt Control Center, Dolby Access) usually install by themselves: Windows brings them from the Store when it installs their driver, without WinGet. Not in a virtual machine, which lacks that hardware.
- **MSI Center and ChatGPT** are also in the `winget` source (`MSI.MSICenter` and `OpenAI.ChatGPT`, from their makers). The catalog uses the Store version, which is their main channel.

### Manufacturer software and Windows components

The first three sections of the catalog are installed before the rest:

- **Windows components:** Visual C++ 2015-2022 (64 and 32 bits), DirectX and .NET Desktop Runtime. Many programs and games need them, so it is worth always ticking them.
- **Graphics and sound:** NVIDIA App, NVIDIA Control Panel, Intel Driver & Support Assistant, Intel Graphics Command Center, Realtek Audio Console, Dolby Access and Thunderbolt Control Center.
- **PC brand:** MSI Center, ASUS Armoury Crate, MyASUS, Lenovo Vantage, Dell Command Update and HP Smart.

Only tick the ones that match your hardware: NVIDIA App, for example, only works with an NVIDIA graphics card.

### Recommendations based on the hardware

When it reaches the list of apps, the installer detects the hardware with WMI:

- The header shows what it found, for example: *Your PC: NVIDIA RTX 4070 · Intel Arc · Intel processor · MSI · Realtek*.
- The apps that suit that PC are in **Recommended for you** and carry **Recommended** in the other lists. Each one's panel says why (for example, *Recommended because you have an NVIDIA graphics card*).
- Nothing is ticked by itself. In **Recommended for you**, **Select all** ticks them all at once.

The detection uses the hardware maker's ID, not the name, so it works even on a freshly formatted PC without drivers.

| If it detects… | It recommends |
|---|---|
| Any PC | Visual C++, DirectX and .NET |
| NVIDIA graphics | NVIDIA App and NVIDIA Control Panel |
| AMD graphics | Shows, below the sections, a button to download AMD Software from amd.com (it is not in WinGet) |
| Intel graphics | Intel Graphics Command Center |
| Intel processor | Intel Driver & Support Assistant |
| Realtek sound | Realtek Audio Console |
| Thunderbolt | Thunderbolt Control Center |
| MSI / ASUS / Lenovo / Dell PC or motherboard | MSI Center / MyASUS (PC) and Armoury Crate (motherboard) / Lenovo Vantage / Dell Command Update |
| Corsair / Razer / SteelSeries peripherals | iCUE / Synapse / SteelSeries GG |
| Logitech LIGHTSPEED receiver (G series) | Logitech G HUB |
| HP printer | HP Smart |

It does not detect whether the PC has Dolby Audio. Nor wired Logitech peripherals, because Windows does not give their model and they could be from the office range.

Several are installed from the **Microsoft Store** (`Source=msstore`). Those apps install as a standard user (`AsUser=Yes`), because they are per-user. NVIDIA App does not, because it is a classic installer that needs administrator rights. **AMD Software: Adrenalin** is in neither WinGet nor the Store: it has to be downloaded from amd.com.

## App catalog: `catalog_apps.csv`

The installer's apps are generated from this CSV at compile time: each row is an app. There are 114, in 15 sections. To add one, add a row and compile again.

| Column | Example | Notes |
|---|---|---|
| Section_ES | `Navegadores` | The group title in the left column (Spanish): best kept short (up to about 22 characters). The rows of a section must be together. |
| Component | `browsers\chrome` | `group\name`, in lowercase, without spaces or accents. |
| Name_ES | `Google Chrome` | The name shown. |
| Description_ES | `El navegador de Google` | One short line (about 60 characters): it appears in the panel, below the name. |
| WingetID | `Google.Chrome.EXE` | Check it with `winget show --id <ID> -e`. |
| Source | `winget` | `winget` or `msstore`; the panel shows it next to the name. |
| Included | `Yes` | Only rows with `Yes` are included (`Si` works too). |
| AsUser | `Yes` | Installs as a standard user: Microsoft Store apps and installers that refuse administrator rights. |
| Note_ES | `Viene con Windows: solo se actualiza` | A free note, shown in the app's panel. |
| Section_EN, Name_EN, Description_EN, Note_EN | `Browsers` | The same texts for the English installer. Empty, the Spanish column is used. |
| WingetID_EN | `Mozilla.Firefox` | Only if the package changes with the language, like Mozilla's. Empty, WingetID is used. |
| Section_FR, Name_FR, Description_FR, Note_FR, WingetID_FR | `Navigateurs` | The same in French. Empty, the English column is used and, if that is empty too, the Spanish one. |
| Profiles | `basic gaming` | The profiles that tick it, separated by spaces: `basic`, `gaming`, `office`, `dev`. |
| OtherIDs | `MSI.MSICenter` | Other packages of the same app, separated by spaces. If a backup brings one of them, this row is ticked instead of installing the app twice. |

Save it from Excel as **CSV (comma delimited)**: `;` separator and ANSI encoding. Inno's preprocessor does not read UTF-8; if the CSV is saved that way, compilation stops with a message instead of producing broken accents. Do not use `;` inside the texts.

## Settings catalog: `catalog_tweaks.csv`

The list on the settings page, in the order they are applied. It is saved like the app catalog.

| Column | Example | Notes |
|---|---|---|
| Section_ES | `Esenciales` | The group (Spanish); its rows must be together. |
| Id | `WPFTweaksTelemetry` | The setting's name in `scripts\winutil_tweaks.json` or `scripts\custom_tweaks.json`. |
| Undo | `Yes` | Applies it the way WinUtil turns a *toggle* off: with the original values and its `UndoScript`. |
| Checked | `Yes` | Ticked by default. |
| Win11 | `Yes` | Only offered on Windows 11. |
| Name_ES, Description_ES | `Desactivar la telemetría` | What is shown in the list and in the panel below (Spanish). |
| Section_EN, Name_EN, Description_EN | `Essentials` | In English. |
| Section_FR, Name_FR, Description_FR | `Essentiels` | In French. |

To add a setting of your own, write it in `scripts\custom_tweaks.json` in WinUtil's format and add its row. To bring in WinUtil's new settings, replace `scripts\winutil_tweaks.json` with its `config\tweaks.json` and run `tools\check_tweaks.ps1`, which warns if any uses something `apply_tweaks.ps1` cannot apply.

## Code structure

The code is in English: names, comments, files and the internal log. The texts the user sees are in `lang\`.

`ReinstallKit.iss` only holds the configuration (`[Setup]`, languages, the scripts that are bundled) and the list of modules. Each module only uses what the previous ones define, so the order of the `#include` lines matters:

| File | What it does |
|---|---|
| `src\common.iss` | Windows constants and functions, `Msg` (texts with placeholders) and the internal log. |
| `src\catalog.iss` | Reads `catalog_apps.csv` at compile time and keeps the apps in the chosen language (`Pick`). |
| `src\theme.iss` | Light/dark colors, icons and the colored bands. |
| `src\dialogs.iss` | The single message and question window (`ShowDialog`). |
| `src\hardware.iss` | Hardware detection with WMI, and the recommendations. |
| `src\backup_page.iss` | Backup pages: save or restore, folders and checks. |
| `src\apps_page.iss` | Apps page: search, categories, profiles, save and load, list and panel. |
| `src\options_page.iss` | Settings page: suggestions, apps at a time, and `catalog_tweaks.csv`, read at compile time. |
| `src\install_page.iss` | Installation page: status, collapsible tasks, skip and timer. |
| `src\tools.iss` | Runs WinGet, PowerShell and other tools, and collects their output. |
| `src\backup.iss` | Saves and restores the drivers (with their counter), the Wi-Fi and the list of apps. |
| `src\tweaks.iss` | Restore point, Windows settings and the user's folders. |
| `src\winget.iss` | WinGet and Internet availability, the installation of each app and its exit codes. |
| `src\parallel.iss` | Several apps at a time: sorts the output of `install_parallel.ps1` into their tasks; skip, cancel and time limit. |
| `src\report.iss` | Summary and Desktop report. |
| `src\usb_restart.iss` | After saving a backup: checks the PC and restarts into the Windows installation USB. |
| `src\installation.iss` | The whole queue, the end, cancelling and the restart question. |
| `src\ready_page.iss` | The summary page before installing. |
| `src\wizard.iss` | Inno Setup's events, which call the modules. |

`scripts\` goes inside the installer; it is extracted to the temporary folder only when needed:

| File | What it is |
|---|---|
| `apply_tweaks.ps1` | Applies one setting in WinUtil's format. |
| `winutil_tweaks.json` | WinUtil's settings, as they are (copied from its main branch on 2026-10-27). |
| `custom_tweaks.json` | Our own settings, in the same format. |
| `LICENSE-winutil.txt` | WinUtil's MIT license. |
| `stream_ansi.ps1` | Converts pnputil's output to UTF-8 live. |
| `toast.ps1` | Sends the Windows notifications, and removes their registry keys at the end. |
| `install_parallel.ps1` | Launches several `winget install` commands at once and passes on each one's output, tagged. |
| `move_user_folders.ps1` | Changes where Documents, Downloads, Pictures, Videos and Music are (the settings page suggestion). |

The program's texts are in `lang\Spanish.isl`, `lang\English.isl` and `lang\French.isl`, in the `[CustomMessages]` section. `%1`, `%2`… are the placeholders the code fills in. When you add or change a text, do it in all three.

Adding another language takes four steps:

1. Create its `.isl` in `lang\`.
2. Add its line to `[Languages]`.
3. Add its columns to both CSV files.
4. Extend `Pick` and the `Langs` macro (in `src\catalog.iss`) and the columns `src\options_page.iss` reads.

## Checks

Before compiling a release, run:

```
powershell -ExecutionPolicy Bypass -File lang\check_languages.ps1
powershell -ExecutionPolicy Bypass -File tools\check_catalog.ps1
powershell -ExecutionPolicy Bypass -File tools\check_tweaks.ps1
```

| Script | What it checks |
|---|---|
| `check_languages.ps1` | That every text the code uses is in all three languages, with the same placeholders. |
| `check_catalog.ps1` | The rules of `catalog_apps.csv`, and that each ID exists in WinGet or the Store. It takes a few minutes; `-SkipWinget` skips that part. |
| `check_tweaks.ps1` | The rules of `catalog_tweaks.csv`, that each `Id` exists in the JSON files, and that `apply_tweaks.ps1 -DryRun` goes through it without changing anything. |

If something fails, they exit with code 1.

## Silent mode

```
ReinstallKit-0.0.1.exe /SILENT /COMPONENTS="browsers\chrome,dev\git"
```

- `/VERYSILENT` shows nothing at all.
- The log is still saved to the Desktop, but it is not opened and nothing is asked.
- Without Internet, no app installation is attempted and the log says so.
- If something needs a restart, Setup restarts the PC by itself, unless you add `/NORESTART`.
- The backup and everything on the settings page (suggestions, restore point, Windows settings, updating everything) are only applied from the wizard, where they can be seen.

## Building

1. Install Inno Setup 6.3 or later (tested with 6.6.1).
2. Open `ReinstallKit.iss` and click **Compile**, or run `ISCC.exe ReinstallKit.iss`.
3. The `.exe` is created at `output\ReinstallKit-0.0.1.exe`.

## Credits

The Windows settings come from [WinUtil](https://github.com/ChrisTitusTech/winutil), by Chris Titus Tech, under the MIT license (`scripts\LICENSE-winutil.txt`). Copyright (c) 2022 CT Tech Group LLC.

## License

ReinstallKit is free software under the [MIT](LICENSE) license. You may use, copy, modify and redistribute it, modified or not and for any purpose, as long as you keep the copyright notice. It is provided as is, without any warranty.

- The compiled `.exe` contains the [Inno Setup](https://jrsoftware.org/isinfo.php) engine, which has [its own license](https://jrsoftware.org/files/is/license.txt).
- The catalog's apps are not bundled: WinGet downloads them from their publishers, and each one has its own license.
- ReinstallKit is not affiliated with Microsoft. Windows and Microsoft Store are trademarks of Microsoft.

To contribute, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Known limitations

- **Skip** and **Cancel** cut the installer short: if it was already installing, the app may be left incomplete and will need reinstalling. One at a time, they also close any open `winget.exe`, not only the installer's own; several at a time, only that app's one.
- Apps with `AsUser=Yes` leave no output in the log, only their result.
- If you open the installer with "Run as administrator", `AsUser` has no effect, because there is no non-elevated user left to launch them from. Open it with a double click.
- If Battle.net fails, the log's command to retry it by hand does not include the language. The language argument only works when typed in `cmd`, so it would install in English.
- In French, Firefox Developer Edition lags a bit behind in WinGet, as in Spanish; Firefox updates itself afterwards.
- The settings cannot be skipped like the apps. None should take more than a few minutes; uninstalling Edge or OneDrive and disabling BitLocker are the slowest.
- Some WinUtil settings depend on the edition. For example, *Disable promoted apps* and *Skip the lock screen* are policies that Windows Home and Pro ignore; their description says so.
