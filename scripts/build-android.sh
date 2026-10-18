#!/usr/bin/env bash
# Release APK for phones + Android TV, signed with the Nox key (lumen.jks), installs over 0.7.x.
#   scripts/build-android.sh [signing dir]   (default /workspace/nox/signing)
# Passwords are read from lumen-passwords.txt into env vars for Gradle; never echoed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN="${1:-/workspace/nox/signing}"
export ANDROID_HOME="${ANDROID_HOME:-/workspace/tools/sdk}"
export JAVA_HOME="${JAVA_HOME:-/workspace/tools/jdk-17.0.20.1+1}"
export PATH="/workspace/tools/flutter/bin:/usr/local/go/bin:$HOME/go/bin:$JAVA_HOME/bin:$PATH"

if [[ ! -f "$ROOT/app/android/app/libs/noxcore.aar" || "${REBUILD_AAR:-0}" == 1 ]]; then
  ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}" "$ROOT/go/mobile/build-aar.sh"
fi

field() { sed -n "s/^$1:[[:space:]]*//p" "$SIGN/lumen-passwords.txt" | head -n1 | tr -d '\r'; }
export NOX_KS_PATH="$SIGN/lumen.jks"
NOX_KS_PASS="$(field 'keystore password')"; export NOX_KS_PASS
NOX_KEY_PASS="$(field 'key password')"; export NOX_KEY_PASS
NOX_KEY_ALIAS="$(field 'alias')"; export NOX_KEY_ALIAS
[[ -n "$NOX_KS_PASS" && -n "$NOX_KEY_ALIAS" ]] || { echo "signing fields not found" >&2; exit 1; }

"$ROOT/scripts/fetch-xray-android.sh"

cd "$ROOT/app"
flutter build apk --release
ls -la build/app/outputs/flutter-apk/app-release.apk
