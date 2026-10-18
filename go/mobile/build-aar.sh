#!/usr/bin/env bash
# Builds app/android/app/libs/noxcore.aar (engine + sing-box libbox) with sagernet/gomobile v0.1.13.
# Needs ANDROID_HOME and ANDROID_NDK_HOME. No OpenVPN/Tailscale/naive tags.
set -euo pipefail
cd "$(dirname "$0")"
TAGS=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
TARGETS=${TARGETS:-android/arm64,android/arm,android/amd64}
GOFLAGS=-mod=mod gomobile bind -target "$TARGETS" -androidapi 24 -javapkg com.lumen.core -libname nox \
  -trimpath -ldflags "-X github.com/sagernet/sing-box/constant.Version=1.14.3 -checklinkname=0 -s -w -buildid=" \
  -tags "$TAGS" -o ../../app/android/app/libs/noxcore.aar ./noxcore
