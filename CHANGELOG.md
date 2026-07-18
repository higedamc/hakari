# Changelog

All notable changes to Hakari are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.4.2] - 2026-07-18

### Added
- Health Planet works for every user: the first-link dialog now takes
  your own developer Client ID alongside the secret (both Keystore-only).

### Changed
- **BREAKING (carried from 0.4.1): package renamed to
  `jp.godzhigella.hakari`** — installs of the old `org.lekt.hakari` do
  not update in place; restore data via "Fetch my data from relays".

## [0.4.1] - 2026-07-18

### Changed
- Package renamed from `org.lekt.hakari` to `jp.godzhigella.hakari`.

## [0.4.0] - 2026-07-18

### Changed
- Full dependency refresh ahead of the Zapstore release: Flutter 3.44.6,
  Gradle 9.6.1 / AGP 9.3.0 (built-in Kotlin), nostr-sdk 0.44.1,
  flutter_riverpod 3, flutter_blue_plus 2, flutter_secure_storage 10,
  share_plus 12. No feature changes.

### Fixed
- Kept the NIP-44 recipient `p` tag on encrypted weight events
  (nostr-sdk 0.39+ strips self-referencing tags by default).

## [0.3.3] - 2026-07-17

### Fixed
- Wellness energy falls back to total calories when no active-calorie
  records exist (the Google Health app writes TOTAL but not ACTIVE
  calories to Health Connect).

## [0.3.2] - 2026-07-17

### Fixed
- Platform-aware store naming on the Auto-sync toggle (last
  "Health Connect / Health" leftover).

## [0.3.1] - 2026-07-17

### Added
- Sleep durations on the readiness card: last night plus the multi-night
  average behind the fat-loss-efficiency estimate.

## [0.3.0] - 2026-07-17

### Added
- Silent Amber signing via ContentProvider (no app switch under "always
  approve"), with foreground fallback, 60s timeout, batch progress and a
  stop button; a rejection aborts the batch.
- Daily wellness (sleep / active energy) persisted in an encrypted Hive
  box and backed up to relays as NIP-44 encrypted kind-30078 events;
  restored by "Fetch my data from relays".
- README: privacy-centric Pixel Watch 2 on GrapheneOS guide.

## [0.2.1] - 2026-07-08

### Added
- Full-history scrollable weight chart (opens at newest data).
- "Check wellness data" diagnostics in Settings.

## [0.2.0] - 2026-07-08

### Added
- Health Planet full-history import (90-day windows, entire record).
- Workout-readiness and fat-loss-efficiency card from Health Connect
  sleep and active energy (Nedeltcheva et al. 2010 based heuristic).

## [0.1.5] - 2026-07-08

### Added
- All Health Planet innerscan tags captured (muscle score, visceral fat
  level 2) across storage, Nostr backup and exports.
- Re-import backfills newly captured metrics into existing entries.

### Changed
- Health Planet linking opens the browser immediately; the client secret
  is asked once, in the same dialog as the authorization code.

## [0.1.3] - 2026-07-08

### Fixed
- Corrected Health Planet link instructions (the authorization code is
  shown on the page, not in the URL).

## [0.1.2] - 2026-07-08

### Changed
- Health Planet client secret is pasted once on-device (Keystore) rather
  than embedded in the APK.

## [0.1.1] - 2026-07-08

### Added
- Launcher icon (adaptive + iOS) matching the in-app Material 3 design.

## [0.1.0] - 2026-07-07

### Added
- Initial release: weight and body-composition logging with standard
  Bluetooth GATT scale support (0x181D / 0x181B), manual entry, trend
  chart, Health Connect / HealthKit sync, TANITA Health Planet cloud
  import, NIP-101h Nostr publishing (kind 1351 + encrypted kind 30078
  backups, NIP-44), Amber (NIP-55) signing, Tor relay routing via Orbot,
  WeightLogger-compatible CSV / JSON export. No telemetry.
