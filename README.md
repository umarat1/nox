# Nox 1.0

One codebase for Windows, Android / Android TV and macOS.
The UI is Flutter and is shared across platforms. The VPN core is Go.

```
app/        Flutter UI (Russian), copies Android Nox: themes, server list/grid/sliders, subscriptions,
            sorting / hide dead / dedup, auto-select, auto-switch, settings, update banner, tray
go/core     subscription parser, sing-box config builder (from pc-ovpn/app/core, OpenVPN removed)
go/engine   App: state, connect, ping (urltest + TCP bound to the physical NIC), updates (ed25519)
go/ipc      loopback HTTP JSON-RPC: 127.0.0.1:<random>, 256-bit token in ipc.json (ACL: SYSTEM/Admins full, Users read)
go/cmd/noxd Windows service "Nox" (LocalSystem): run | install | uninstall | start | stop | version
go/cmd/signupdate  ed25519 signer for update.json
go/mobile   gomobile AAR (com.lumen.core.noxcore): engine + libbox in the Android app process
app/android Android phone + TV (package com.lumen.vpn, VpnService, leanback launcher, tile, boot)
installer/  Inno Setup 7 script (per-machine, registers the service, migrates/removes Nox 0.8.x)
third_party/windows  qwdtt.exe 1.4.4, sing rule sets, LICENSES.txt (xray.exe is fetched by CI)
third_party/android  <abi>/libqwdtt.so (libxray.so fetched by scripts/fetch-xray-android.sh)
.github/workflows/windows.yml  windows-latest build -> Nox-Setup-<ver>.exe (+ signed update.json)
```

No OpenVPN on any platform. Engines: sing-box, qWDTT, SSTP, and Xray-core for XHTTP servers.

XHTTP (`vless://…?type=xhttp`, also trojan) is not in sing-box. Such servers are stored as
`{"type":"_xray","xray":<Xray outbound>}`. When one is selected, Xray-core runs it behind a loopback
SOCKS5 port and sing-box chains to it, so TUN, routing, DNS and stats stay in sing-box. Ping works the
same way: one Xray instance serves all XHTTP servers on separate ports for the URL test.
For the disconnected URL test, server domains are resolved through public DNS (with DoH fallback) and
fake-IP answers are skipped, so a stale or poisoned system resolver can't break pings.

## Android / TV
`scripts/build-android.sh` (`SPLIT=1` for per-ABI APKs: armeabi-v7a versionCode 1xxx, arm64-v8a 2xxx) builds the AAR if needed (`go/mobile/build-aar.sh`) and fetches Xray (pinned
sha256). It then builds a release APK signed with lumen.jks (passwords come from
lumen-passwords.txt through env vars). versionCode is the pubspec build number, which is above 0.7.71's 99.
At first start, `files/lumen-data.json` from 0.7.x is imported.

- Per-app split tunnelling (Settings → «Приложения через VPN»): all apps / only selected
  (`addAllowedApplication`) / all except selected (`addDisallowedApplication`). Stored as
  `splitMode`/`splitApps`, applied to the TUN as sing-box `include_package`/`exclude_package`;
  changing it while connected reconnects. Nox itself is always outside the VPN.
- SSTP on Android: pure-Go MS-SSTP client (TLS → PPP/MS-CHAPv2 → IPCP) bridged into VpnService
  TUN (same full-tunnel path as Windows RAS). Subscription SSTP links appear when the UA starts
  with `Nox/` (or is plain `sing-box x.y.z`).
- qWDTT captcha: qWDTT runs with `-captcha-mode auto` (its Go solver first). When it asks for a
  manual WebView solve (`CAPTCHA_SOLVE|manual|<url>|…` on stdout), the engine exposes
  `captcha {id,url}` in GetState; `CaptchaActivity` opens VK's page and sends `success_token`
  back with `SolveCaptcha(id, token)` → `CAPTCHA_RESULT|token` on qWDTT's stdin. Requests for
  headless "auto" WebView solves are declined so qWDTT moves on. Windows has no captcha UI yet
  (qWDTT keeps `-captcha-mode rjs` there).

## Windows architecture
* `noxd.exe` runs as a LocalSystem service. It owns TUN, routes, sing-box/qwdtt processes and SSTP (RAS).
  It keeps running when the window is closed. The UI needs no UAC.
* `Nox.exe` (Flutter) runs as the user. It reads `%ProgramData%\Nox\ipc.json` (port + token) and calls the
  service. Per-user things stay in the UI: the system proxy (HKCU Internet Settings) and autostart (HKCU Run, `--tray`).
* `%ProgramData%\Nox` (state, logs, downloads) is locked to SYSTEM and Administrators.
* Update flow: `version.json` → `"nox2-windows": {versionName, url, sha256, sig}`. The service downloads the
  installer and verifies sha256 plus the ed25519 `sig` (public key in `go/engine/update.go`). It then runs the
  installer with `/VERYSILENT`, and the restarted service brings the UI back into the user's session.
* First start after 0.8.x: the installer silently uninstalls 0.8.x but keeps user data. The UI then
  imports `%LOCALAPPDATA%\Nox\state.json` (or `VPS`). OpenVPN servers are dropped during the import.

## Build
Flutter cannot build Windows desktop apps on Linux. CI does it on `windows-latest` (see the workflow).

Local (Linux, for development):
```
cd go && go test ./... && GOOS=windows go build -o ../build/noxd.exe ./cmd/noxd
cd app && flutter test && flutter build web --dart-define=NOX_MOCK=true   # UI preview with demo data
go run ./cmd/noxd run -data /tmp/noxd   # dev daemon; then: flutter test test/service_it_test.dart
```
Windows (manual): `flutter build windows`, stage `dist\app` + `dist\core` as in the workflow, then
`ISCC /DAppVersion=1.0.6 /DDist=..\dist installer\nox.iss`.

## Updates (`version.json`)

Android 1.0 reads **top-level** fields (same as 0.7.x; old clients ignore unknown keys):

- `versionCode` (int) — compared to the app build number (106 for 1.0.6)
- `versionName`, `url`, `sha256`, `notes`
- optional per-ABI: `url_arm64` / `sha256_arm64`, `url_armv7` / `sha256_armv7` (fallback `url_armeabi_v7a`)
- Windows signed channel: `nox2-windows` object with `versionName`, `url`, `sha256`, `sig` (ed25519), `notes`

Envelope icon in the header (0.7.x «конверт»): red badge when an update is available; tap re-checks and offers install.

## Secrets (CI)
* `NOX_UPDATE_KEY`: ed25519 private key for update signing (`go run ./cmd/signupdate -gen key`; keep it offline).
* `WIN_CERT_PFX_BASE64`, `WIN_CERT_PASSWORD`: optional Authenticode certificate (removes SmartScreen warnings).
