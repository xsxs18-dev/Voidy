# Changelog

## 1.0.3

- Stop force-killing Safari and package managers during manual and scheduled cleaning.
- Skip running/suspended apps, app extensions and files in use; show skipped work in the result.
- Preserve cache directories, database families, symlinks and recent files. Evaluate the 24-hour age
  limit per file so an old temporary directory cannot cause new files to be deleted.
- Respect Safari and package-manager exclusions, and apply exclusion changes to existing schedules.
- Check whether scheduled cleaning is actually loaded. Validate settings before replacing them,
  report launchctl failures and restore the previous schedule after failed activation.
- Enforce the privacy-category restriction inside the helper for both schedule creation and execution.
- Serialize helper mutations to prevent manual and automatic cleans from overlapping.
- Keep incomplete APT downloads; remove the permission to autoremove essential packages and report
  failed package simulations.
- Restrict large-file deletion to regular files, avoiding recursive deletion of protected descendants.
- Handle interrupted process waits and helper failures correctly; use subsecond history timestamps.
- Add isolated filesystem/process/schedule regression tests and require them before release builds.
- Publish only from Main and retain previous releases for rollback.

Validation: rootless/roothide package builds and macOS regression tests. No physical iPhone XR on
iOS 18.4 was available during development; device behavior still needs confirmation.

## 1.0.2

- Free storage now matches the Settings app: purgeable space (caches and content iOS can remove on its own) counts as free. Before, Voidy could show only a few GB free and warn that storage is almost full (#2)

## 1.0.1

- Added Simplified Chinese (zh-Hans) localization – thanks to heiyanquan123!
- Voidy now supports English, German and Simplified Chinese

## 1.0

Initial release.

- Cleans app caches, Safari cache, temporary files, crash reports, logs, package cache, tweak caches and repository lists
- Privacy cleaning for browsing history, cookies & website data and keyboard learning (always with confirmation, never automatic)
- Exclude individual apps from cleaning
- Smart Insights with a health score, crash-loop detection and one-tap suggestions
- Tweak manager with search, filters, "Disable all" and one-tap restore
- Large file finder, orphaned package removal and unused language cleanup
- Launch daemon manager with protected core services
- Respring, rebuild icon cache, userspace reboot, ldrestart and reboot
- Automatic background cleaning on a schedule
- Cleaning history with chart
- Home screen quick actions: Smart Clean and Respring
- Native dark interface with a deep violet accent
- rootless and roothide support
- English and German
