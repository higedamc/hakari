# Hakari（秤）

Privacy-first weight & body-composition logger — **Flutter × Rust FFI**, Nostr-native.

Inspired by [kochka/WeightLogger](https://github.com/kochka/WeightLogger) (feature set) and
[higedamc/meiso](https://github.com/higedamc/meiso) (architecture: flutter_rust_bridge 2.12 +
cargokit + nostr-sdk + Amber + Tor).

## Features

- **Measurements**: weight + full TANITA-style body composition (body fat %, body water %,
  muscle mass, visceral fat rating, bone mass, BMR, metabolic age), manual entry, 90-day trend chart.
- **BLE scales**: standard Bluetooth SIG Weight Scale Service (0x181D) and Body Composition
  Service (0x181B) with full 0x2A9D / 0x2A9C GATT parsing. TANITA note: modern TANITA consumer
  scales (BC-401/768, RD-9xx) use a proprietary, account-bound BLE protocol — they are surfaced
  in scan results, while any scale exposing the standard services (and legacy HMM smartLAB "WS"
  units, as supported by WeightLogger) works end-to-end.
- **Health Connect / Apple Health**: read & write weight and body fat (`health` 13.x),
  auto-sync on save, 90-day import with dedupe.
- **Nostr (NIP-101h)**: publishes each measurement as kind **1351** weight events
  (`unit`/`t:health`/`t:weight` tags) plus a kind **30078** (NIP-78) encrypted full-entry backup
  (`d = hakari:entry:<uuid>`), NIP-44 self-encrypted by default; restore via relay fetch.
- **Amber (NIP-55)**: external-signer login, event signing and NIP-44 encrypt/decrypt via
  `nostrsigner:` intents + ContentProvider fallback — the app never sees your secret key.
  Local-key mode is also available (see tradeoff note in `lib/data/nostr/nsec_store.dart`).
- **Tor / Orbot**: relay websockets can be routed through Orbot's SOCKS5 proxy
  (`socks5://127.0.0.1:9050`, configurable) via nostr-sdk connection proxy.
- **Export**: WeightLogger-compatible CSV and versioned JSON backup, via system share sheet.
- **No telemetry.** No analytics, no crash reporting, no network calls other than the relays
  and health stores you configure.

## Architecture

```
lib/domain/        contracts: entities, repository/service interfaces, failures (Phase 0)
lib/core/di/       Riverpod DI seams (overridden in main.dart)
lib/data/          implementations: local (Hive), ble, health, signer (Amber), nostr (Rust FFI), export
lib/presentation/  Material 3 UI (Riverpod)
lib/bridge_generated/  flutter_rust_bridge 2.12 codegen (do not edit)
rust/              nostr core: nostr-sdk 0.37, NIP-101h event builders, relay pool, SOCKS5 proxy
cargokit/          vendored build tool — compiles the Rust crate per ABI during gradle build
```

The crate is named `rust` (→ `librust.so`); cargokit locates artifacts by cargo *package* name,
which must match the gradle `libname` and the FRB loader stem.

## Build

```bash
flutter pub get
flutter_rust_bridge_codegen generate   # only after changing rust/src/api.rs
flutter build apk --debug --target-platform android-arm64
```

Requires Rust with Android targets, NDK 28.0.13004108 (pinned in `android/app/build.gradle.kts`
and `rust/.cargo/config.toml`), minSdk 26 (Health Connect).

## Tests

```bash
flutter test          # 86 tests: GATT parsers, bech32, CSV, Hive repos, health mapping, NIP-101h codec
cd rust && cargo test # 10 tests: event kinds/tags, key roundtrip, NIP-44, proxy parsing, local signing
```
