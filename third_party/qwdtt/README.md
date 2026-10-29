# libqwdtt patches

`third_party/android/*/libqwdtt.so` = upstream wg-turn-client go_client
(commit a296c57, "Release 1.4.4") + the patches in this directory, built by
`scripts/build-libqwdtt.sh` (QW_SRC=<upstream checkout>, ANDROID_NDK_HOME=…).

0001-liveness-turn-auto.patch (nox 2.1.9):
* data-flow liveness: if local WireGuard sent real packets but nothing came
  back for 15 s (server WG always answers with a passive keepalive within
  10 s), or no worker gets READY in 30 s, or no config in 40 s, all TURN
  sessions are torn down and re-established at once;
* `-turn-auto`: the same event flips the TURN transport UDP <-> TCP
  (mobile carriers like MTS black-hole UDP to VK TURN after the handshake);
  stdout gets `TRANSPORT|udp|tcp|<reason>`, the nox engine remembers TCP per
  server for 12 h (go/engine/qwdtt_transport.go).
* `-no-liveness` disables the detector.

The Windows qwdtt.exe is a different build and is not patched; the engine
passes `-turn-auto` only on Android.
