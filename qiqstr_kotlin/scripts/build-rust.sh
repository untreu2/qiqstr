#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${PROFILE:-release}"
ABIS="${ABIS:-arm64-v8a x86_64}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$(ls -d "$HOME/Library/Android/sdk/ndk/"* | sort -V | tail -1)}"
cd "$ROOT/../qiqstr_rust/uniffi"
ARGS=()
for abi in $ABIS; do ARGS+=(-t "$abi"); done
JNI="$ROOT/app/src/main/jniLibs"
rm -rf "$JNI"
if [ "$PROFILE" = "release" ]; then
  cargo ndk "${ARGS[@]}" --platform 26 -o "$JNI" build --release --lib
else
  cargo ndk "${ARGS[@]}" --platform 26 -o "$JNI" build --lib
fi
find "$JNI" -type f ! -name 'libqiqstr_core.so' -delete
cargo build --lib
OUT="$ROOT/app/src/main/java"
rm -rf "$OUT/com/qiqstr/core"
cargo run --bin uniffi-bindgen -- generate --library target/debug/libqiqstr_core.dylib --language kotlin --out-dir "$OUT" --no-format
echo "Built $JNI and $OUT/com/qiqstr/core"
