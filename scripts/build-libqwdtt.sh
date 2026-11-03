#!/usr/bin/env bash
# Rebuild third_party/android/*/libqwdtt.so from upstream wg-turn-client
# (go_client, tag "Release 1.4.4", a296c57) + nox patches in third_party/qwdtt.
#   QW_SRC=/path/to/qwdtt-checkout ANDROID_NDK_HOME=... scripts/build-libqwdtt.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QW_SRC="${QW_SRC:?set QW_SRC to an upstream checkout}"
NDK="${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME}"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
git -C "$QW_SRC" worktree add -q --detach "$WORK/src" a296c57
trap 'git -C "$QW_SRC" worktree remove --force "$WORK/src"; rm -rf "$WORK"' EXIT
for p in "$ROOT"/third_party/qwdtt/*.patch; do git -C "$WORK/src" apply "$p"; done
cd "$WORK/src/go_client"
go mod tidy -e >/dev/null
go test -run 'Stall|Keepalive|NoReady|FixedMode|RawMode' .
build() { # abi goarch clang
  echo "building $1"
  GOOS=android GOARCH="$2" GOARM=7 CGO_ENABLED=1 CC="$TC/$3" \
    go build -trimpath -ldflags="-s -w -checklinkname=0" -o "$ROOT/third_party/android/$1/libqwdtt.so" .
}
build arm64-v8a arm64 aarch64-linux-android21-clang
build armeabi-v7a arm armv7a-linux-androideabi21-clang
build x86_64 amd64 x86_64-linux-android21-clang
ls -la "$ROOT"/third_party/android/*/libqwdtt.so
