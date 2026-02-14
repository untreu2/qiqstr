# qiqstr ─ Cross-platform Nostr client
Fast, easy-to-use, and complete Nostr client with built-in Bitcoin wallet.

## Supported NIPs

| NIP | Description |
|-----|-------------|
| [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) | Basic protocol flow description |
| [NIP-02](https://github.com/nostr-protocol/nips/blob/master/02.md) | Follow List |
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
| [NIP-51](https://github.com/nostr-protocol/nips/blob/master/51.md) | Lists |
| [NIP-56](https://github.com/nostr-protocol/nips/blob/master/56.md) | Reporting |
| [NIP-57](https://github.com/nostr-protocol/nips/blob/master/57.md) | Lightning Zaps |
| [NIP-59](https://github.com/nostr-protocol/nips/blob/master/59.md) | Gift Wrap |
| [NIP-62](https://github.com/nostr-protocol/nips/blob/master/62.md) | Request to Vanish |
| [NIP-65](https://github.com/nostr-protocol/nips/blob/master/65.md) | Relay List Metadata |
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
| 1984 | Reporting |
| 1059 | Gift Wrap |
| 9734 | Zap Request |
| 9735 | Zap Receipt |
| 10000 | Mute List |
| 10002 | Relay List Metadata |
| 24242 | Blossom Auth |
| 27235 | HTTP Auth |
| 30000 | Follow Sets |
| 30001 | Bookmark List |
| 30023 | Long-form Article |

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI | Flutter |
| State management | flutter_bloc |
| Native layer | Rust via flutter_rust_bridge |
| Nostr protocol | nostr-sdk 0.44 (Rust) |
| Local database | LMDB via nostr-lmdb |
| Secure storage | flutter_secure_storage |
| Routing | go_router |
| DI | get_it |

## Architecture

Layered architecture with strict dependency direction:

```
UI -> Presentation -> Data -> Domain
```

- **Domain** -- Entities and mappers, no framework imports
- **Data** -- Repositories, services, sync logic
- **Presentation** -- BLoCs with events and states
- **UI** -- Screens and widgets

All cryptographic operations, event signing, relay communication, NIP-44 encryption, NIP-17 gift wrapping, NIP-19 encoding, and database access run in Rust. The Dart side interacts through auto-generated bridge code.

## Building

Prerequisites: Flutter SDK, Rust toolchain, and flutter_rust_bridge CLI.

```sh
flutter pub get
flutter_rust_bridge_codegen generate
flutter run
```
