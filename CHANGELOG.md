# Changelog

Release builds are numbered `<version>.<build>` (e.g. `1.1.4`). Entries below list the changes per version.

## 1.2

### Changed
- The app is now called **Voidly** (package `com.xsxs18.voidly`). Installing it replaces the old package automatically; cleaning history is carried over.

## 1.1

### New
- Completely redesigned, native interface: grouped lists, system colors, swipe actions, search and pull-to-refresh
- Full light and dark mode support
- Storage bar showing used, reclaimable and free space at a glance
- New minimal app icon
- "Smart Insights" section with a health score and one-tap suggestions
- Swipe left on an app in App Caches to exclude it from cleaning
- Swipe left on a large file to delete it

### Fixed
- Sizes of empty categories show "0 KB" instead of "Zero KB"
- "Smart Clean" button no longer wraps onto two lines
- Tweak names with a leading space (e.g. Choicy, Crane) are shown correctly

### Improved
- Cleaner package description
- Primary actions are pinned to the bottom of the screen
- Schedule settings are saved from the navigation bar

## 1.0

### Initial release
- Cleans app caches, Safari cache, temporary files, crash reports, logs, package cache, tweak caches and repository lists
- Privacy cleaning for browsing history, cookies and keyboard learning (always with confirmation)
- Tweak manager with search, disable all and one-tap restore
- Large file finder, orphaned package removal and unused language cleanup
- Launch daemon manager with protected core services
- Respring, icon cache rebuild, userspace reboot, ldrestart and reboot
- Automatic background cleaning on a schedule
- Cleaning history
- Home screen quick actions
- rootless and roothide support
- English and German
