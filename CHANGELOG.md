# Changelog

All notable user-facing changes are documented in this file.

## [2.4] - 2026-11-12

### Changed

- Bumped app version to 2.4 (build 37).

### Fixed

- Included administrator-authorized device recovery after reinstall/reset, durable enrollment retries and recovery during catalog refresh. See [verification and deployment limits](docs/IDENTITY_RECOVERY_FIX_20261112.md).

## [2.3] - 2026-11-12

### Changed

- Bumped app version to 2.3 (build 36).
- Unified engine routing across iOS 16–27 (legacy 3105, worse_query on-device direct container access, AirLift fallback).
- Hardened HWID persistence, Keychain recovery and authentication resilience.

## [2.0] - 2026-11-07

### Changed

- Modernized Profile tab UI with Dark Gaming theme (Xanh `#147DFF` — Tím `#5865F2` — Hồng `#EC4899`).
- Streamlined Settings view.
- Bumped app version to 2.0.

## [1.2.10] - 2026-11-06

### Fixed

- Completed on-device AirLift pairing from the validated staging record instead of rejecting the transient `waitingSettings` state as an empty credential file.
- Preserved atomic file protection and Keychain ordering when promoting a new AirLift pairing record.
- Added device-identity recovery and protected-download diagnostics needed by installations whose previous identity was revoked.

### Verification

- Added pairing-completion and device-recovery regression checks to the unsigned IPA workflow.

## [1.0.1] - 2026-08-15

### Added

- Bundle-tree Patch workspace v2 under `On My iPhone/3105/Patches`, synchronized automatically when applying or exporting.
- Multiple independent Files tabs with preserved navigation state.
- ZIP extraction with path, symbolic-link, CRC, and available-space validation.
- Responsive iPad split-view and landscape navigation.
- Home toggles for showing or hiding Cleaner and Wallpaper features.

### Changed

- Patch creation from an app-container file or folder now captures the stable bundle identifier and editable destination tree automatically.
- Patch package imports no longer use the previous fixed payload-size or file-count ceiling; practical device storage and memory still apply.
- Files and Patch screens now use consistent grouped cards, compact icons, balanced nested rows, and stable search presentation.
- Legacy v1 `.3105` packages remain importable and usable.

### Fixed

- Patch Restore now restores files that existed before Apply, removes files introduced by the patch, and removes patch-created folders after they become empty.
- File navigation remains at the current folder when switching app sections and restores the correct folder independently for each Files tab.
- Empty Patch and Cleaner actions now share the same visual treatment.
- Corrected PosterBoard wallpaper activation guidance and the iOS 27 Collections prerequisite.
- Refined navigation icon rendering and nested file-row spacing.

### Compatibility

- Verified iOS 26.0–26.6.1.
- Verified iOS 27 Developer Beta 1–4, including Public Beta 1–2 mappings listed in the app.
- Added iPhone and iPad interface support; device-level features still require enterprise signing.

## [1.0 beta 3] - 2026-08-14

### Added

- Bundle-based App Data Browser with MHA-C2 container discovery.
- Native file operations: search, multi-file import, rename, delete, create file/folder, and conflict handling.
- Portable `.3105` patch projects with optional password protection and file/folder rules.
- Limited per-app cleaner for `Library/Caches` and `tmp`.
- Wallpaper Lab for validated `.tendies` packages with installation receipts and targeted reset.
- English, Vietnamese, and Simplified Chinese localization.

### Changed

- Simplified the app into a five-tab, native SwiftUI layout inspired by focused iOS container tools.
- Moved the enterprise-signing notice below device information on Home.
- Refined the orange accent, empty states, actions, and navigation presentation.

### Fixed

- Stabilized persistent search presentation in app and file browsers.
- Fixed native document selection for replacement files and `.3105` package imports.
- Resolved bundle-name mapping for enumerated app containers where metadata is available.
- Limited wallpaper reset to active content installed by 3105.
- Corrected Cleaner layout when no removable app data is found.

### Compatibility

- Verified iOS 26.0–26.6.1.
- Verified iOS 27 beta 1–4 builds listed in the app.
- Unlisted iOS 27 builds remain disabled until explicitly verified.
