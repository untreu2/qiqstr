#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
cargo fmt --manifest-path rust/Cargo.toml --check
cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --locked --manifest-path rust/Cargo.toml
cargo build --locked --manifest-path rust/Cargo.toml
flutter analyze --no-pub
flutter test --no-pub
git diff --check

if [[ $# -gt 0 ]]; then
  flutter test --no-pub integration_test -d "$1"
fi
