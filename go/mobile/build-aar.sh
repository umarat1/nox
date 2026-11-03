#!/usr/bin/env bash
# Builds app/android/app/libs/noxcore.aar (engine + sing-box libbox) with sagernet/gomobile v0.1.13.
# Needs ANDROID_HOME and ANDROID_NDK_HOME. No OpenVPN/Tailscale/naive tags.
set -euo pipefail
cd "$(dirname "$0")"
# A leftover bind dir makes gomobile fail with "go_main.go: file exists".
rm -rf build
mkdir -p ../../app/android/app/libs
TAGS=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
TARGETS=${TARGETS:-android/arm64,android/arm}
GOFLAGS=-mod=mod gomobile bind -target "$TARGETS" -androidapi 24 -javapkg com.lumen.core -libname nox \
  -trimpath -ldflags "-X github.com/sagernet/sing-box/constant.Version=1.14.3 -checklinkname=0 -s -w -buildid= -extldflags=-Wl,-z,max-page-size=16384" \
  -tags "$TAGS" -o ../../app/android/app/libs/noxcore.aar ./noxcore

# Drop leftover ELF sections. LOAD alignment (16 KB) is unchanged by strip.
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-}/ndk/28.2.13676358}"
STRIP="$(find "$NDK/toolchains/llvm/prebuilt" -type f -name llvm-strip -print -quit 2>/dev/null || true)"
AAR="$(pwd)/../../app/android/app/libs/noxcore.aar"
if [[ -n "$STRIP" && -f "$AAR" ]]; then
  tmp=$(mktemp -d)
  unzip -q "$AAR" -d "$tmp"
  find "$tmp" -name 'libnox.so' -exec "$STRIP" --strip-unneeded {} \; || true
  staged="$tmp/repack.aar"
  (cd "$tmp" && zip -q -r -X "$staged" . -x 'repack.aar')
  mv -f "$staged" "$AAR"
  rm -rf "$tmp"
fi
