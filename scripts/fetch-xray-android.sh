#!/usr/bin/env bash
# Xray-core (XHTTP servers) for Android: third_party/android/<abi>/libxray.so, pinned + checksum verified.
# Packaged as a "native library" so it lands executable in nativeLibraryDir (like libqwdtt.so).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V=26.3.27
declare -A ZIP=([arm64-v8a]=Xray-android-arm64-v8a.zip [x86_64]=Xray-android-amd64.zip [armeabi-v7a]=Xray-linux-arm32-v7a.zip)
declare -A SHA=(
  [arm64-v8a]=57149ffd48b629c07bf76938e73ab2729fde5910091497eab3e93d1c190f4c1b
  [x86_64]=bfa1dd4cb3cd94f92af6c718ac6933cc84bd3ddd8343aa1e413162152930bee5
  [armeabi-v7a]=c7265ae13c63ca0241a037df4ef960ad37938c8a67d984cc08834b2cfdf5654b
)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for abi in "${!ZIP[@]}"; do
  out="$ROOT/third_party/android/$abi/libxray.so"
  mark="$ROOT/third_party/android/.xray-$abi"
  [[ -s "$out" && "$(cat "$mark" 2>/dev/null)" == "$V" ]] && continue
  curl -fsSL -o "$tmp/x.zip" "https://github.com/XTLS/Xray-core/releases/download/v$V/${ZIP[$abi]}"
  echo "${SHA[$abi]}  $tmp/x.zip" | sha256sum -c --quiet
  unzip -o -q "$tmp/x.zip" xray -d "$tmp/$abi"
  mkdir -p "$(dirname "$out")"; install -m 755 "$tmp/$abi/xray" "$out"; echo "$V" > "$mark"
  echo "xray $V -> $abi"
done
