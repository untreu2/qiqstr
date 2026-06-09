# qiqstr

A cross-platform Nostr client for Android and iOS with a built-in Bitcoin wallet.

qiqstr is built with Flutter and Rust, combining a responsive mobile UI with high-performance native cryptography, relay communication, and local storage. All protocol-level operations — event signing, encryption (NIP-44), gift wrapping (NIP-17/NIP-59), bech32 encoding (NIP-19), and database access (LMDB) — run in Rust through an auto-generated bridge layer.

## Features

- **Social feed** — View and publish text notes, long-form articles, reposts, and reactions
- **Private messaging** — End-to-end encrypted direct messages via NIP-17 gift wrap
- **Bitcoin wallet** — Built-in wallet via Nostr Wallet Connect (NIP-47) and Breez SDK (Spark)
- **Lightning zaps** — Send and receive zaps on notes and profiles
- **QR scanning** — Scan and generate QR codes for Nostr identities and invoices
- **Media support** — Inline images, video playback, GIF search (Giphy), and media saving
- **Relay management** — Configurable relay lists with negentropy syncing (NIP-77)
- **Moderation** — Mute lists, reporting (NIP-56), and event deletion requests
- **Identity** — NIP-05 verification, mnemonic seed backup (NIP-06), and bech32 entities
- **Localization** — English, Turkish, and German

## Supported NIPs

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

## Supported Event Kinds

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

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI | Flutter (Dart SDK ^3.5.4) |
| State management | flutter_bloc |
| Native layer | Rust 2021 via flutter_rust_bridge 2.11.1 |
| Nostr protocol | nostr-sdk 0.44 (Rust) |
| Local database | LMDB via nostr-lmdb |
| Bitcoin wallet | Breez SDK Spark |
| Secure storage | flutter_secure_storage |
| Routing | go_router |
| DI | get_it |

## Architecture

Layered architecture with a strict dependency direction:

```
UI -> Presentation -> Data -> Domain
```

| Layer | Path | Responsibility |
|-------|------|----------------|
| Domain | `lib/domain/` | Entities and mappers — no framework imports |
| Data | `lib/data/` | Repositories, services, sync logic |
| Presentation | `lib/presentation/` | BLoCs with events and states |
| UI | `lib/ui/` | Screens and widgets |
| Core | `lib/core/` | DI (GetIt), routing (go_router), base classes |

All cryptographic operations, event signing, relay communication, NIP-44 encryption, NIP-17 gift wrapping, NIP-19 encoding, and database access run in Rust. The Dart side interacts through auto-generated bridge code. The Rust API modules are organized as:

| Module | Responsibility |
|--------|----------------|
| `crypto` | Key derivation, signing, encryption |
| `database` | LMDB storage and queries |
| `relay` | WebSocket relay connections and syncing |
| `events` | Nostr event construction and parsing |
| `nip17` | Private direct messages and gift wrapping |
| `nip19` | bech32 encoding and decoding |
| `nwc` | Nostr Wallet Connect protocol |
| `cashu` | Cashu/ecash operations |

## Prerequisites

- **Flutter SDK** >= 3.5.4
- **Rust toolchain** (install via [rustup](https://rustup.rs/))
- **flutter_rust_bridge CLI** v2.11.1

  ```sh
  cargo install flutter_rust_bridge_codegen@2.11.1
  ```

- **Platform tooling** — Android SDK and/or Xcode depending on your target

## Building

1. Clone the repository and set up environment variables:

   ```sh
   cp .env.example .env
   # Edit .env to add your GIPHY_API_KEY and BREEZ_API_KEY
   ```

2. Install dependencies and generate bridge code:

   ```sh
   flutter pub get
   flutter_rust_bridge_codegen generate
   ```

3. Run the app:

   ```sh
   flutter run
   ```

To build a release APK or IPA:

```sh
flutter build apk
flutter build ipa
```

## Project Structure

```
qiqstr/
  lib/
    core/           DI modules, routing, base classes
    data/           Repositories, services, sync logic
    domain/         Entities and mappers
    presentation/   BLoCs (events, states)
    ui/             Screens and widgets
    src/rust/       Auto-generated bridge code (do not edit)
    l10n/           Localization ARB files (en, tr, de)
  rust/
    src/api/        Rust API modules (crypto, relay, database, ...)
  assets/           Icons and images
  android/          Android platform project
  ios/              iOS platform project
```

## Contributing

Contributions are welcome. When submitting changes, please follow these guidelines:

- **Architecture** — Respect the layered dependency direction (UI -> Presentation -> Data -> Domain). UI code must not import from `data/` or `domain/` directly.
- **State management** — Use `flutter_bloc` exclusively. Every feature gets its own BLoC with separate event and state files.
- **Dependency injection** — Use `get_it`. Register new services, repositories, or BLoCs in the appropriate module under `lib/core/di/modules/`.
- **Rust changes** — Edit source files under `rust/src/api/`, then regenerate the bridge with `flutter_rust_bridge_codegen generate`. Never edit files in `lib/src/rust/`.
- **Code style** — Follow Dart conventions (`snake_case` files, `PascalCase` classes, `camelCase` variables). Avoid comments that restate what the code already says.
- **Localization** — User-facing strings go in the ARB files under `lib/l10n/`. Never hardcode display text.
- **Linting** — Fix all lint warnings before submitting. The project uses `flutter_lints` and `bloc_lint`.

See `AGENTS.md` for the full architecture and coding conventions reference.

## License

This project is licensed under the [MIT License](LICENSE).
