# qiqstr monorepo

- `qiqstr_flutter/` contains the Flutter client. Read `qiqstr_flutter/AGENTS.md` before changing it.
- `qiqstr_swift/` contains the native SwiftUI client. Read `qiqstr_swift/AGENTS.md` before changing it.
- `qiqstr_mac/` contains the native macOS client (SwiftUI). It compiles the Swift app's sources from `qiqstr_swift/Qiqstr` with a Mac shell. Read `qiqstr_mac/AGENTS.md` before changing it.
- `qiqstr_kotlin/` contains the native Android client (Kotlin, Jetpack Compose), a port of the Swift app. Read `qiqstr_kotlin/AGENTS.md` before changing it.
- `qiqstr_rust/` is the shared Rust core (crate `qiqstr`) used by both apps: nostr-sdk, LMDB, relays, NWC, Cashu, NIP-17, and Marmot behind the `marmot` feature. Put Rust logic here, not in an app.
- Two bridges wrap the core, both generated from `qiqstr_rust/src/api`:
  - `qiqstr_rust/uniffi` (crate `qiqstr_core`, UniFFI) is shared by the Swift and Kotlin apps. `gen_ffi.py` there regenerates `src/ffi.rs`. Swift builds an XCFramework from it (`qiqstr_swift/scripts/build-rust.sh`, iOS and macOS slices, used by both `qiqstr_swift` and `qiqstr_mac`); Kotlin builds `.so` files and Kotlin bindings (`qiqstr_kotlin/scripts/build-rust.sh`).
  - `qiqstr_flutter/rust` (flutter_rust_bridge) belongs to the Flutter app.
  After changing the core's public API, regenerate both bridges and rebuild every app.
- Run build, generation, and test commands from the relevant directory. Check the core with `cargo fmt --check`, `cargo clippy --all-targets --features marmot -- -D warnings`, and `cargo test --features marmot` in `qiqstr_rust/`.

## Browser

Zen Browser is for the user only. Never open, drive, script, quit, or read data from Zen (`/Applications/Zen.app`, `~/Library/Application Support/zen`), including with computer use.

Use Google Chrome for all browser work. Never run a bare `open <url>`; use `open -a "Google Chrome" <url>`.
