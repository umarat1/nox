#!/usr/bin/env bash
# Copy qwdtt / xray / naive into an ABI-split jniLibs dir and strip leftover ELF
# sections. The APK stores these uncompressed (extractNativeLibs=false); smaller
# files mean a smaller sideload. LOAD alignment is left as the linker wrote it.
set -euo pipefail
OUT="${1:?output dir}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/third_party/android"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-}/ndk/28.2.13676358}"
STRIP=""
if [[ -d "$NDK" ]]; then
  STRIP="$(find "$NDK/toolchains/llvm/prebuilt" -type f -name llvm-strip -print -quit 2>/dev/null || true)"
fi
rm -rf "$OUT"
mkdir -p "$OUT"
for abi in arm64-v8a armeabi-v7a; do
  [[ -d "$SRC/$abi" ]] || continue
  mkdir -p "$OUT/$abi"
  for name in libqwdtt.so libnaive.so libxray.so; do
    [[ -f "$SRC/$abi/$name" ]] || continue
    cp -f "$SRC/$abi/$name" "$OUT/$abi/$name"
    if [[ -n "$STRIP" ]]; then
      "$STRIP" --strip-unneeded "$OUT/$abi/$name" || true
    fi
  done
done
