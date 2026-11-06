# qiqstr

Two clients in one repository, each with its own app and Rust build configuration.

| App | Directory | Stack |
| --- | --- | --- |
| Flutter | [qiqstr_flutter](qiqstr_flutter/) | Flutter, BLoC, flutter_rust_bridge |
| Native iOS | [qiqstr_swift](qiqstr_swift/) | SwiftUI, Liquid Glass, UniFFI |

## Flutter

```sh
cd qiqstr_flutter
flutter pub get
flutter run
```

See the [Flutter README](qiqstr_flutter/README.md) for platform setup and configuration.

## Native iOS

```sh
cd qiqstr_swift
scripts/build-rust.sh
xcodegen generate
open Qiqstr.xcodeproj
```

See the [Swift README](qiqstr_swift/README.md) for the native app and Rust bridge details.

## Working in this repository

Run app commands from the corresponding app directory. Each app's `AGENTS.md` defines its architecture and development rules. The Flutter and Swift commit histories are preserved in this repository.

[Terms](TERMS.md) · [License](LICENSE)
