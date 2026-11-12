<div align="center">

<img src="assets/main_icon_white.svg" alt="qiqstr logo" width="120" />

# qiqstr

**A fast, easy-to-use Nostr client for Android and iOS — with a built-in Bitcoin Lightning wallet.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey.svg)](#installation)
[![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B.svg?logo=flutter)](https://flutter.dev)
[![Native: Rust](https://img.shields.io/badge/native-Rust-DEA584.svg?logo=rust&logoColor=white)](https://www.rust-lang.org)

</div>

---

qiqstr is a mobile client for [Nostr](https://nostr.com), the decentralized, open, and
censorship-resistant social protocol. It lets you publish notes and articles, follow people,
exchange end-to-end encrypted direct messages, and send or receive Bitcoin Lightning payments —
without creating an account with a central qiqstr server. Your private identity key is stored
locally and signs events; your public key identifies those events on relays.

Under the hood, qiqstr pairs a [Flutter](https://flutter.dev) UI with a [Rust](https://www.rust-lang.org)
core: Nostr signing, encryption, relay connections, and event storage run in native Rust
through [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge).

## Features

- **Full social client** — publish and read text notes, long-form articles (NIP-23), threads, reposts, reactions, and quotes.
- **Encrypted direct messages** — private DMs using NIP-17 gift-wrapped messages (NIP-44 / NIP-59).
- **Built-in Bitcoin wallet** — send and receive Lightning payments and zaps over Nostr Wallet Connect (NIP-47), with built-in wallet onboarding through the Breez Spark SDK and Cashu token support.
- **You own your identity** — private identity keys are generated on-device and stored in OS-backed secure storage. Relays receive signed events and public keys.
- **Local identity and wallet keys** — identity keys and Spark recovery keys are stored on-device. Connected NWC wallets and Cashu mints have their own custody and service models.
- **Fast local data** — events are stored and synced locally in an embedded LMDB database, with efficient Negentropy syncing (NIP-77).
- **Localized** — available in English, Turkish, and German.

<details>
<summary><strong>Supported NIPs</strong></summary>

| NIP | Description |
|-----|-------------|
| [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) | Basic protocol flow description |
| [NIP-02](https://github.com/nostr-protocol/nips/blob/master/02.md) | Follow List |
| [NIP-04](https://github.com/nostr-protocol/nips/blob/master/04.md) | Direct Messages (used by NWC) |
| [NIP-05](https://github.com/nostr-protocol/nips/blob/master/05.md) | Mapping Nostr keys to DNS-based internet identifiers |
| [NIP-06](https://github.com/nostr-protocol/nips/blob/master/06.md) | Basic key derivation from mnemonic seed phrase |
| [NIP-09](https://github.com/nostr-protocol/nips/blob/master/09.md) | Event Deletion Request |
| [NIP-10](https://github.com/nostr-protocol/nips/blob/master/10.md) | Text Notes and Threads |
| [NIP-17](https://github.com/nostr-protocol/nips/blob/master/17.md) | Private Direct Messages |
| [NIP-18](https://github.com/nostr-protocol/nips/blob/master/18.md) | Reposts |
| [NIP-19](https://github.com/nostr-protocol/nips/blob/master/19.md) | bech32-encoded entities |
| [NIP-21](https://github.com/nostr-protocol/nips/blob/master/21.md) | nostr: URI scheme |
| [NIP-23](https://github.com/nostr-protocol/nips/blob/master/23.md) | Long-form Content |
| [NIP-25](https://github.com/nostr-protocol/nips/blob/master/25.md) | Reactions |
| [NIP-27](https://github.com/nostr-protocol/nips/blob/master/27.md) | Text Note References |
| [NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md) | Encrypted Payloads (Versioned) |
| [NIP-47](https://github.com/nostr-protocol/nips/blob/master/47.md) | Nostr Wallet Connect |
| [NIP-51](https://github.com/nostr-protocol/nips/blob/master/51.md) | Lists |
| [NIP-56](https://github.com/nostr-protocol/nips/blob/master/56.md) | Reporting |
| [NIP-57](https://github.com/nostr-protocol/nips/blob/master/57.md) | Lightning Zaps |
| [NIP-59](https://github.com/nostr-protocol/nips/blob/master/59.md) | Gift Wrap |
| [NIP-62](https://github.com/nostr-protocol/nips/blob/master/62.md) | Request to Vanish |
| [NIP-65](https://github.com/nostr-protocol/nips/blob/master/65.md) | Relay List Metadata |
| [NIP-77](https://github.com/nostr-protocol/nips/blob/master/77.md) | Negentropy Syncing |
| [NIP-98](https://github.com/nostr-protocol/nips/blob/master/98.md) | HTTP Auth |

</details>

<details>
<summary><strong>Supported event kinds</strong></summary>

| Kind | Description |
|------|-------------|
| 0 | User Metadata |
| 1 | Text Note |
| 3 | Follow List |
| 5 | Event Deletion |
| 6 | Repost |
| 7 | Reaction |
| 14 | Direct Message (rumor) |
| 15 | File Message (rumor) |
| 62 | Request to Vanish |
| 1059 | Gift Wrap |
| 1984 | Reporting |
| 9734 | Zap Request |
| 9735 | Zap Receipt |
| 10000 | Mute List |
| 10001 | Pin List |
| 10002 | Relay List Metadata |
| 23194 | NWC Request |
| 23195 | NWC Response |
| 24242 | Blossom Auth |
| 27235 | HTTP Auth |
| 30000 | Follow Sets |
| 30001 | Bookmark List |
| 30023 | Long-form Article |

</details>

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI | Flutter |
| State management | flutter_bloc |
| Native layer | Rust via flutter_rust_bridge |
| Nostr protocol | nostr-sdk 0.44 (Rust) |
| Local database | LMDB via nostr-lmdb |
| Wallet | Breez Spark SDK + Nostr Wallet Connect + Cashu (cdk) |
| Secure storage | flutter_secure_storage |
| Routing | go_router |
| Dependency injection | get_it |

## Architecture

The required dependency direction for new code is:

```
UI -> Presentation -> Data -> Domain
```

- **Domain** — entities and mappers, with no framework imports.
- **Data** — repositories, services, and sync logic.
- **Presentation** — BLoCs with their events and states.
- **UI** — screens and widgets, with business logic delegated to BLoCs.

Existing screens still contain layering and state-management violations. See the
[review report](docs/FIVE_PASS_REVIEW.md) for the remaining migration work.

All cryptographic operations, event signing, relay communication, NIP-44 encryption,
NIP-17 gift wrapping, NIP-19 encoding, and database access run in Rust. The Dart side
interacts exclusively through auto-generated bridge code.

## Installation

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) `>=3.44.0` (Dart `>=3.12.0`); verified with Flutter 3.44.4.
- [Rust toolchain](https://www.rust-lang.org/tools/install); verified with Rust 1.96.0.
- [`flutter_rust_bridge_codegen`](https://github.com/fzyzcjy/flutter_rust_bridge) CLI:
  ```sh
  cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
  ```
- An Android or iOS device/emulator and the matching platform toolchain (Android SDK / Xcode). iOS 15 or later is required.

### Build and run

```sh
# 1. Clone the repository
git clone https://github.com/untreu2/qiqstr.git
cd qiqstr/qiqstr_flutter

# 2. Provide build-time configuration
cp build_config.example.json build_config.json
# then fill in BREEZ_API_KEY

# 3. Fetch Dart dependencies
flutter pub get

# 4. Generate the Rust <-> Dart bridge
flutter_rust_bridge_codegen generate

# 5. Run the app
flutter run --dart-define-from-file=build_config.json
```

> **Note:** `build_config.json` supplies `BREEZ_API_KEY` (Lightning wallet) at
> compile time and is excluded from version control. Use the same
> `--dart-define-from-file=build_config.json` option for release builds.

## Release configuration

Breez Spark Flutter 0.26.1 and `flutter_rust_bridge` 2.13.0 are pinned together. Upgrade the
SDK, Rust crate, Dart package, and generator as one migration, then verify wallet recovery
and payments.
Use the committed Dart and Rust lockfiles to retain tested dependency resolutions.
CI pins the host Rust toolchain; Cargokit currently uses the `stable` toolchain for both
the app bridge and Breez mobile native builds, so their compiler version is not pinned
independently of the build environment.

Android releases require `android/key.properties` with `storeFile`, `storePassword`,
`keyAlias`, and `keyPassword`. Release builds no longer fall back to a debug signing key.
Verify the application ID and signing identity before publishing; the current Android ID
is `com.example.qiqstr`. An update to an already published app must retain its existing
application ID and signing identity and use a higher build number. Keep signing files
and `build_config.json` out of version control.

For an Android ARM64 release build, retain the resolved lockfiles and allow Flutter to
regenerate release-specific plugin registration:

```sh
flutter pub get --enforce-lockfile
release_lock_checksums="$(mktemp)"
shasum -a 256 pubspec.lock rust/Cargo.lock ios/Podfile.lock > "$release_lock_checksums"
flutter build apk --release --target-platform android-arm64 \
  --dart-define-from-file=build_config.json
shasum -a 256 -c "$release_lock_checksums"
rm "$release_lock_checksums"
```

Require the build and checksum checks to succeed. Avoid `--no-pub` for this release
command after running tests: Flutter 3.44.4 can otherwise retain test-only plugin
registration and fail compilation. See
[Flutter issue #163774](https://github.com/flutter/flutter/issues/163774).
Without release signing configuration, the resulting APK is unsigned.

Android cloud backup and device transfer are disabled for app data containing wallet
state and private messages. Back up identity and wallet recovery keys before changing
devices. User-added certificate authorities are trusted only by debug builds.
Cashu has separate local seed and proof storage; identity and Spark recovery backups do
not restore it. Cashu recovery/export remains a release blocker for wallets holding funds.

## Usage

1. **Create or import an identity.** On first launch, generate a new key pair or import an
   existing private key (`nsec`) or mnemonic seed phrase (NIP-06). Your private key is stored
   in your device's secure storage and used locally to sign events.
2. **Explore the feed.** Browse notes from people you follow, discover content, and read
   long-form articles.
3. **Interact.** Reply, react, repost, and quote. Send end-to-end encrypted direct messages.
4. **Connect a wallet.** Link any NWC-compatible wallet, or set up the built-in Spark wallet, to
   send and receive Lightning payments and zap content you enjoy.

> **Back up your identity and wallet recovery keys separately.** The Nostr seed phrase
> restores your identity; Spark uses a separate recovery key. Losing either can prevent recovery. See [TERMS.md](TERMS.md)
> for the full privacy policy and terms of use.

## Verification

Run `./tool/verify.sh` on macOS or Linux to verify the dependency lockfile, Rust formatting,
strict Clippy checks, and Rust tests, build the native library, run the Dart analyzer, and
execute the Dart, native integration, and widget tests. CI runs the same checks and builds
the iOS simulator app and an unsigned iOS device release. An independent Android job
builds an unsigned ARM64 release APK and checks
16 KB ZIP and native-library ELF LOAD alignment. Host tests load
`rust/target/debug/librust_lib_qiqstr.dylib` on macOS or the `.so` on Linux. Set
`QIQSTR_NATIVE_LIBRARY` to use another build path.

Run the separate dependency security gate with:

```sh
cargo install cargo-audit --version 0.22.2 --locked
./tool/audit_dependencies.sh
```

The independent CI security job checks both the app's Rust lockfile and Breez's bundled
native lockfile. It currently fails on 31 vulnerability advisories in the Breez lockfile;
these are documented release blockers. Passing tests alone does not clear this gate.

Pass a simulator/device ID to include mobile integration tests:

```sh
flutter devices
./tool/verify.sh <device-id>
```

The native suite uses generated test identities and temporary LMDB databases. Its NWC
relay runs on loopback. Onboarding tests mock secure storage; a separate device test uses
the real secure-storage plugin with isolated temporary keys. The real-startup test
redirects filesystem paths to a temporary directory. Startup checks connect to the default
public relays; tests do not publish public content or send real payments.

See [the five-pass review](docs/FIVE_PASS_REVIEW.md) for findings, validation, and remaining
coverage limits.

## Contributing

Contributions are welcome! To get started:

1. Fork the repository and create a feature branch.
2. Follow the project conventions documented in [AGENTS.md](AGENTS.md) — especially the layered
   architecture, BLoC patterns, and code-style rules.
3. Run the analyzer and tests, and fix all lint warnings before opening a pull request:
   ```sh
   ./tool/verify.sh
   ```
4. Keep the layering intact (UI must never import from `data/` or `domain/` directly) and never
   edit generated files under `lib/src/rust/`, `lib/l10n/app_localizations*.dart`, or
   `*.g.dart`. After changing Rust code, regenerate the bridge with
   `flutter_rust_bridge_codegen generate`.

For questions, feedback, or bug reports, please open an issue on
[GitHub](https://github.com/untreu2/qiqstr/issues).

## License

qiqstr is released under the [MIT License](LICENSE), Copyright (c) 2024 emir yorulmaz.

The qiqstr name, logo, and associated branding are the property of the developer and are not
covered by the MIT grant. See [TERMS.md](TERMS.md) for details.
