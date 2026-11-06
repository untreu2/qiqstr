#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-release}"
TARGETS="${TARGETS:-aarch64-apple-ios aarch64-apple-ios-sim}"
cd "$ROOT/rust"
export IPHONEOS_DEPLOYMENT_TARGET=26.0
for t in $TARGETS; do
  cargo build --profile "$PROFILE" --target "$t" --lib
done
DIR=release; [ "$PROFILE" = "dev" ] && DIR=debug
cargo build --lib
OUT="$ROOT/QiqstrCore"
rm -rf "$OUT/Sources/QiqstrCore/qiqstr_core.swift" "$OUT/QiqstrCoreFFI.xcframework" "$ROOT/build/bindings"
mkdir -p "$OUT/Sources/QiqstrCore" "$ROOT/build/bindings/headers"
cargo run --bin uniffi-bindgen -- generate --library target/debug/libqiqstr_core.a --language swift --out-dir "$ROOT/build/bindings"
mv "$ROOT/build/bindings/qiqstr_core.swift" "$OUT/Sources/QiqstrCore/"
cp "$ROOT/build/bindings/qiqstr_coreFFI.h" "$ROOT/build/bindings/headers/"
cp "$ROOT/build/bindings/qiqstr_coreFFI.modulemap" "$ROOT/build/bindings/headers/module.modulemap"
ARGS=()
for t in $TARGETS; do
  ARGS+=(-library "target/$t/$DIR/libqiqstr_core.a" -headers "$ROOT/build/bindings/headers")
done
xcodebuild -create-xcframework "${ARGS[@]}" -output "$OUT/QiqstrCoreFFI.xcframework" >/dev/null
echo "Built $OUT/QiqstrCoreFFI.xcframework"
