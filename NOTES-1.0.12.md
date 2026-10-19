# Nox 1.0.12 — notes (Android hotfix)

## qWDTT «клиент завершился» — cause
`startQwdtt` (go/engine/app.go) starts a watcher goroutine after qwdtt delivers its WireGuard
config. When that qwdtt process exits, the watcher set `errMsg = "qWDTT: клиент завершился"`
when status was connected **or connecting** and then called `stopAll()` **unconditionally**.
It never checked that the process was still the current one (`a.qw`).

Any reconnect therefore killed itself:
1. `Disconnect()` → `stopAll()` kills the old qwdtt.
2. `Connect()` sets status "connecting".
3. The old watcher wakes up, sees "connecting", sets the error and calls `stopAll()`, killing
   the new session.

Triggers: server switch while connected (`Select`), auto-switch (`autoswitch.go`), and the
reconnect after settings changes. 1.0.10 added the «Маршрутизация» toggles and turned
RU-apps routing on via migration (SetVer 110), so reconnects became frequent. That makes it
look like a 1.0.10 regression. The Xray and SSTP watchers already had this check.

Checked and not the cause: qwdtt runs inside the app process, and the app UID is excluded
from its own VPN (`addDisallowedApplication(packageName)` is still there in 1.0.10). So
VK relay traffic always goes direct, whatever the RU-apps or LAN-bypass settings are.
qwdtt args and binary have not changed since 1.0.1.

## Fixed (commit bf49413, go/engine/qwdtt_watch.go)
- The watcher ignores exits of a qwdtt that is no longer `a.qw`. `stopAll` clears it before
  killing.
- The real reason is shown: exit code/signal plus the QwdttFatal line or the last 3 log lines.
- Unexpected exits auto-restart with backoff 2/4/8/16/30 s, also when the restart itself fails.
  The counter resets after a 2-minute stable session. Disconnect cancels the pending restart.
  Fatal (auth/captcha) errors don't retry.
- Tests: qwdtt_watch_test.go.
- Version 1.0.12+120 (split vc 2120/1120, universal 120).

## Left
- Verify on the emulator (reconnect/switch with qWDTT) and build signed APKs plus sha256-1.0.12.txt.
- Deferred features (not started in code): proxy chains in «+», manual SSTP form, Exclave-like
  manual forms for all protocols.
