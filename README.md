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
all without accounts, servers, or middlemen. Your identity is a cryptographic key pair that
never leaves your device.

Under the hood, qiqstr pairs a [Flutter](https://flutter.dev) UI with a [Rust](https://www.rust-lang.org)
core: every cryptographic operation, relay connection, and database access runs in native Rust
through [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge), giving you a smooth,
fast experience with a small, auditable trusted base.

## Features

- **Full social client** — publish and read text notes, long-form articles (NIP-23), threads, reposts, reactions, and quotes.
- **Encrypted direct messages** — private DMs using NIP-17 gift-wrapped messages (NIP-44 / NIP-59).
- **Built-in Bitcoin wallet** — send and receive Lightning payments and zaps over Nostr Wallet Connect (NIP-47), with optional one-tap onboarding via [Coinos](https://coinos.io).
- **You own your identity** — keys are generated on-device and stored in OS-backed secure storage; they never reach the developer or any relay.
- **Self-custodial by design** — no central server, no analytics, no profiling.
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
| Wallet | Nostr Wallet Connect + Cashu (cdk) |
| Secure storage | flutter_secure_storage |
| Routing | go_router |
| Dependency injection | get_it |

## Architecture

qiqstr follows a layered architecture with a strict, one-directional dependency flow:

```
UI -> Presentation -> Data -> Domain
```

- **Domain** — entities and mappers, with no framework imports.
- **Data** — repositories, services, and sync logic.
- **Presentation** — BLoCs with their events and states.
- **UI** — screens and widgets, with no business logic.

All cryptographic operations, event signing, relay communication, NIP-44 encryption,
NIP-17 gift wrapping, NIP-19 encoding, and database access run in Rust. The Dart side
interacts exclusively through auto-generated bridge code.

## Installation

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `>=3.5.4`)
- [Rust toolchain](https://www.rust-lang.org/tools/install)
- [`flutter_rust_bridge_codegen`](https://github.com/fzyzcjy/flutter_rust_bridge) CLI:
  ```sh
  cargo install flutter_rust_bridge_codegen
  ```
- An Android or iOS device/emulator and the matching platform toolchain (Android SDK / Xcode).

### Build and run

```sh
# 1. Clone the repository
git clone https://github.com/untreu2/qiqstr.git
cd qiqstr

# 2. Provide the required environment variables
cp .env.example .env
# then edit .env and fill in GIPHY_API_KEY and BREEZ_API_KEY

# 3. Fetch Dart dependencies
flutter pub get

# 4. Generate the Rust <-> Dart bridge
flutter_rust_bridge_codegen generate

# 5. Run the app
flutter run
```

> **Note:** `.env` requires `GIPHY_API_KEY` (GIF picker) and `BREEZ_API_KEY` (Lightning wallet).
> See [`.env.example`](.env.example) for the expected keys.

## Usage

1. **Create or import an identity.** On first launch, generate a new key pair or import an
   existing private key (`nsec`) or mnemonic seed phrase (NIP-06). Your private key is stored
   in your device's secure storage and never leaves it.
2. **Explore the feed.** Browse notes from people you follow, discover content, and read
   long-form articles.
3. **Interact.** Reply, react, repost, and quote. Send end-to-end encrypted direct messages.
4. **Connect a wallet.** Link any NWC-compatible wallet, or onboard instantly with Coinos, to
   send and receive Lightning payments and zap content you enjoy.

> Bitcoin and Lightning transactions are irreversible, and qiqstr is self-custodial. **Back up
> your private key** — if you lose it, your identity cannot be recovered. See [TERMS.md](TERMS.md)
> for the full privacy policy and terms of use.

## Contributing

Contributions are welcome! To get started:

1. Fork the repository and create a feature branch.
2. Follow the project conventions documented in [AGENTS.md](AGENTS.md) — especially the layered
   architecture, BLoC patterns, and code-style rules.
3. Run the analyzer and tests, and fix all lint warnings before opening a pull request:
   ```sh
   flutter analyze
   flutter test
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
