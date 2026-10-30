# Contributing

Thank you for wanting to improve ReinstallKit. Before opening a pull request, please keep the following in mind.

## Code rules

- The code is in English: names, comments, files and the internal log.
- What the user sees goes in `lang\Spanish.isl`, `lang\English.isl` and `lang\French.isl`, always in all three.
- Each module in `src\` only uses what the previous ones define. Keep the order of the `#include` lines in `ReinstallKit.iss`; it is explained under *Code structure* in the README.
- Whatever the installer creates for itself (registry keys, temporary files, settings it changes for a while) is undone when it closes.

## Adding an app or a setting

- **Apps:** one row in `catalog_apps.csv`. The columns are described in `src\catalog.iss`.
- **Windows settings:** one row in `catalog_tweaks.csv`. Its `Id` must exist in `scripts\winutil_tweaks.json` or `scripts\custom_tweaks.json`.
- Save both CSV files from Excel as **"CSV (comma delimited)"**, which uses the ANSI encoding. Saved as UTF-8, they do not compile.

## Before submitting

1. Run the checks from the *Checks* section of the README (`check_languages.ps1`, `check_catalog.ps1` and `check_tweaks.ps1`). They must finish without errors.
2. Compile with Inno Setup 6.3 or later.
3. Test the installer in a virtual machine, not on your own PC: it installs programs, changes Windows settings and may restart.

## Reporting a bug

Open an issue and attach the log the installer leaves on the Desktop (`ReinstallKit log <date>.txt`). Review it before uploading: it may include the PC's name and paths with your user name.

By submitting code, you agree to publish it under the project's [MIT license](LICENSE).
