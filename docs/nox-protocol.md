# nox-protocol (`noxp://`)

Russian summary for operators is at the end. The link scheme is `noxp://`, not `nox://`: `nox://` is already the phone-to-TV pairing QR.

This is a prototype cover transport for NOX. It is not a new cipher. A passive observer should see a TLS 1.3 session whose ClientHello looks like a browser, and an active prober who does not have the key should get an ordinary website. **No transport is undetectable.** A censor who blocks by IP reputation, who blocks all TLS to unpopular hosts, or who can compare a flow with a real browser over time can still disrupt it. The point is to not look like VLESS, Reality, XHTTP, Hysteria2 or AmneziaWG.

## Threat model

The censor in view is TSPU-style DPI on the path between a user in Russia and the VPS:

- **Known-protocol fingerprints.** First packets of VLESS/Reality, XHTTP, Hysteria2, AmneziaWG and similar are classified. We do not speak those protocols on the wire.
- **TLS ClientHello fingerprints (JA3/JA4).** A Go or custom handshake is itself a signature. The client uses [uTLS](https://github.com/refraction-networking/utls) presets (`chrome`, `firefox`, `safari`, `ios`, `random`).
- **Length and timing.** Constant record sizes and perfectly periodic packets are a signal. Frames are padded to a profile (`browse`, `video`, `mixed`) and writes can sleep a few milliseconds (`jitter`).
- **“Fully encrypted” entropy.** Raw encrypted UDP/TCP without a TLS or HTTP header is classified as a tunnel. The payload sits inside real TLS 1.3 and HTTP/2, HTTP/3, or ordinary HTTPS requests.
- **Active probing.** The censor finishes a TLS handshake and sends a normal HTTP request, or replays a captured client packet. Without the key the server answers like a website (built-in page, or a reverse proxy of a site you control). It does not RST, and it does not return a distinct error.
- **Replay.** A captured handshake must not open a second session.
- **Many short flows.** Streams are multiplexed on one long-lived connection.
- **CDN and fronting.** When the direct IP is blocked, the same bytes can ride as normal HTTPS requests to a CDN, or with a TLS SNI that differs from the HTTP Host where a CDN still allows that.

Out of scope, and not solved:

- Blocking the server IP because it is on a VPN list, or blocking the whole subnet.
- A censor who terminates TLS with a private CA installed on the device (they then see HTTP). TSPU does not do that for the general population; a corporate proxy might.
- Correlation of “user went offline, a long TLS flow to this IP started”.
- Website fingerprinting by a model trained on this exact implementation.
- QUIC Initial-packet fingerprints. HTTP/3 uses quic-go’s crypto/tls, not a browser QUIC stack. See limitations.

## Cryptography

Nothing here is home-grown.

| Piece | What | Library |
| --- | --- | --- |
| Outer layer | TLS 1.3 | `crypto/tls` on the server, uTLS on the TCP client |
| Handshake | Noise `NKpsk0` (spec rev. 34): `-> psk, e, es` / `<- e, ee` | `github.com/flynn/noise` |
| DH | X25519 | Noise’s `DH25519` |
| AEAD | ChaCha20-Poly1305 | Noise’s `CipherChaChaPoly` |
| Hash / KDF | SHA-256, HKDF-SHA-256 | Noise and `golang.org/x/crypto/hkdf` |

Pattern name on the wire (inside TLS): `Noise_NKpsk0_25519_ChaChaPoly_SHA256`. Prologue is the ASCII string `noxp/1`.

The PSK is `HKDF-SHA256(ikm=password, salt=server_public_key, info="noxp/psk-v1")`. The client knows the server’s X25519 public key (it is in the link). An empty password is allowed and is weaker: the link itself is then the only secret.

The first Noise message carries an authenticated payload of 8-byte Unix time plus 16 random bytes. The server rejects skew over 120 seconds and remembers the 32-byte ephemeral public key for 3 minutes, so a replay of the same message fails.

## Carriers

One subscription can list several. The client tries them in order, but puts the last carrier that worked on this network first (`nox-paths.json`).

| Name | What the censor sees | When to use |
| --- | --- | --- |
| `h2` | TLS 1.3 + HTTP/2 to your domain. One long POST. | Default. Direct to the VPS. |
| `h3` | QUIC / HTTP/3 to the same port. | When UDP is open and TCP to the IP is not. Fingerprint is weaker than `h2`; see limitations. |
| `cdn` | Many ordinary HTTPS POSTs (batched), not one infinite body. Works behind a CDN that buffers request bodies. | When the VPS IP is blocked but a CDN in front of it is not. Slower. |
| `front` | Same as `h2`, but TCP/SNI go to `front` (or the link host) and the HTTP Host is `host`. | Only where the CDN still forwards a mismatched Host. Most large CDNs do not. |

Authentication is not a TLS client certificate (that shows up in the handshake) and not a distinctive header in the clear. It is a cookie named `sid` whose value is the Noise client message, inside TLS. A wrong or missing cookie is ignored and the request is served as the cover site.

`cdn` uses the same path with `?b=1`. The first response sets a cookie `nx` (an opaque session id). Later POSTs carry ciphertext only. The id does not let a CDN decrypt the Noise session; at most it can reset the session by injecting garbage.

## Wire format

### TLS

Server: TLS 1.3 only, ALPN `h2` and `http/1.1` on TCP, ALPN `h3` on UDP. Certificate must be publicly trusted (Let’s Encrypt or similar) for a name you control. A self-signed certificate is a signal; `-self-signed` exists for loopback tests only.

ClientHello: uTLS preset. ALPN offered is `h2`, `http/1.1`, matching the preset’s usual list. User-Agent is chosen from the same family as the preset (`fp=chrome` → Chrome 133, which is what `HelloChrome_Auto` is in uTLS 1.8.2).

### HTTP (h2, h3, front)

```
POST <path> HTTP/2
cookie: sid=<base64url(noise_msg1)>
content-type: application/json     (browse, mixed)
              video/mp4            (video)
cache-control: no-cache
user-agent: <matches fp>
```

Response, only if `noise_msg1` decrypts:

```
200
content-type: <same family>
body: uint16be(len(noise_msg2)) || noise_msg2 || frames...
```

The request body is the client’s frames. Both directions are flushed per frame so a record is not one endless buffer. If auth fails, the body is HTML (or the cover proxy) and the status is 200, same as a normal GET.

### Frames (inside Noise transport messages)

Each direction is a sequence of:

```
uint16be ciphertext_length
ciphertext = ChaCha20-Poly1305(plaintext)
```

Plaintext, padded with random bytes up to a size drawn from the profile (padding is inside the AEAD, so it is not visible as a separate field):

```
uint8  type
uint32 stream_id
uint16 payload_len
bytes  payload
bytes  padding   (ignored)
```

Types: `1` OPEN (TCP or UDP), `2` DATA, `3` CLOSE, `4` PING, `5` UDP datagram, `6` ACK.

OPEN payload: `uint8 flags (1=udp) || uint16 port || uint8 host_len || host`. ACK with an empty payload means the dial succeeded; otherwise the payload is an error string.

Many SOCKS connections share one HTTP connection. A slow stream blocks the others (head-of-line). That is acceptable for a prototype and is called out below.

### Padding profiles

`browse`: 128, 256, 384, 512, 700, 1024, 1400 bytes, weighted to the smaller ones.

`video`: 4096, 8192, 12000, 16384.

`mixed`: both.

Default jitter (max sleep before a write): browse 15 ms, video 6 ms, mixed 10 ms. `jitter=0` in the link disables it. Jitter is a trade against throughput; leave it small.

These sizes influence TLS record sizes because each frame is flushed. HTTP/2 adds its own 9-byte frame header, so the on-wire record is not exactly the inner size. That is intentional: we avoid a single constant length, we do not claim the distribution matches a specific website.

### CDN batch

First POST `?b=1` with the `sid` cookie and a finite body. Response is `uint16be || msg2 || frames` plus `Set-Cookie: nx=...`.

Later POSTs send up to 32 KiB of ciphertext and wait up to `Hold` (server default 200 ms) for bytes in the other direction. Idle polls are the main fingerprint of this mode: a steady request rate. Use it when `h2` to the IP is blocked, not as the daily default.

## Subscription

```
noxp://<base64url-pubkey>:<password>@host:port?carrier=h2,h3,cdn&sni=example.com&host=example.com&path=/api/v1/events&profile=mixed&fp=chrome#Name
```

| Query | Meaning |
| --- | --- |
| `carrier` | Comma list: `h2`, `h3`, `cdn`, `front`. Default `h2`. |
| `sni` | TLS Server Name. Default: link host. Must match the certificate. |
| `host` | HTTP authority if it should differ (fronting). |
| `front` | Dial this host for carrier `front` (CDN edge). |
| `path` | Request path. Default `/api/v1/events`. |
| `profile` | `browse`, `video`, `mixed`. |
| `fp` | `chrome`, `firefox`, `safari`, `ios`, `random`. |
| `jitter` | Max padding delay in milliseconds. `0` disables. |
| `insecure` | `1` skips certificate checks. Tests only. |

The app stores this as an in-process extra outbound (`kind: nox`) and exposes a local SOCKS5, same as Juicity or Mieru. TUN, routing and DNS stay in sing-box.

Per-network memory:

- Inside NOX, the winning carrier is stored in `nox-paths.json` in the profile directory.
- Across protocols, a successful connect is stored in `path-memory.json`. If **автопереключение** is on and NOX fails to dial, the client tries another server, preferring a type that already worked on this network. The same memory is consulted by the existing auto-switch loop.

## Why each check is harder, and where it still works

| Check | What we do | What remains |
| --- | --- | --- |
| VLESS/Reality/XHTTP/Hysteria/AWG signatures | Different protocol, inside TLS | A custom classifier trained on *this* build can still exist. Rotate profiles and paths. |
| JA3/JA4 | uTLS browser preset | Presets go stale. Update uTLS when browsers change. HTTP/2 SETTINGS from Go are only partly Chrome-like (header table 65536, max header list 262144, max frame 16384). The connection window is still Go’s default 1 GiB, and the SETTINGS order is Go’s order. A TLS-terminating observer can tell. Passive TSPU does not see SETTINGS. |
| Entropy / “random UDP” | Real TLS records, real HTTP framing | The *shape* of a long upload+download can still be learned. |
| Record sizes | Random padding per profile | Not a recording of a real site. An ML model with enough samples may separate it. |
| Timing | Optional jitter, plus CDN polling | Jitter is uniform, not a human. CDN mode is periodic. |
| Active probe | Cover page or reverse proxy, HTTP 200, no RST | The built-in page will not match a famous SNI. Use your own domain and `-cover` if the domain should show a real site. Go’s ServerHello is not nginx’s. “This IP speaks Go TLS” is common (Caddy) but not invisible. |
| Replay | Time in the Noise payload + ephemeral cache | Clock skew over 2 minutes fails closed. A captured cookie replayed *before* the real client consumes the slot delays that client; the client must handshake again (new ephemeral). |
| Short connections | Mux on one session | One session is one long flow, which is itself a feature some classifiers use. |
| HTTP/3 | Implemented | QUIC ClientHello is not Chrome’s. Treat `h3` as a fallback, not the stealthiest mode. |
| Domain fronting | `front` carrier | Often blocked by the CDN, not by TSPU. Do not count on Google, AWS or Cloudflare. |

## Server

Binary: `go/cmd/nox-server`. Unit: `deploy/nox-server.service`. Installer: `scripts/install-nox-server.sh` (Ubuntu 24.04, does not edit xray).

```
cd go && go build -o nox-server ./cmd/nox-server
sudo ./nox-server -genkey /etc/nox/identity
```

The command prints the public key, password and a sample `noxp://` link. Put that link in the subscription.

`/etc/nox/server.json`:

```json
{
  "listen": "0.0.0.0:8443",
  "h3": "0.0.0.0:8443",
  "cert": "/etc/nox/fullchain.pem",
  "key": "/etc/nox/privkey.pem",
  "identity": "/etc/nox/identity",
  "cover": "https://your-real-site.example",
  "path": "/api/v1/events",
  "profile": "mixed"
}
```

Port 8443 avoids taking 443 from xray. A real certificate is required:

```
certbot certonly --standalone -d your.domain
```

Then `systemctl enable --now nox-server`. The service user is `nox`. It may bind to 443 via `CAP_NET_BIND_SERVICE`.

Clients without the key receive the cover site (cookie stripped before proxying) or the built-in “Field notes” page. That page is original placeholder text, not a copy of anyone’s site. Replace it with `-cover` for anything you expect a human or a prober to compare against a real name.

The server dials whatever the authenticated client asks (it is an exit node). Firewall it the same way you firewall the rest of the VPN.

## Client

Add the `noxp://` line to the subscription the app already fetches. The server shows up as type **NOX**. Select it like any other server. It cannot be placed in a proxy chain (same as XHTTP and qWDTT).

Enable **автопереключение** if NOX should give up and move to a VLESS/Hysteria/other line from the same subscription when the dial fails or the tunnel later goes dead. Carrier rotation (`h2` then `h3` then `cdn`) happens even when that setting is off.

There is no separate toggle. The subscription is the configuration.

## Tests and a small benchmark

```
cd go && go test ./noxproto/ ./core/ ./engine/ ./extra/ -count=1
```

Covered: Noise round-trip and wrong password, replay, stale timestamp, padded frame sizes, unauthenticated HTTP gets HTML (not a reset), bad cookie gets the same HTML, loopback echo, two streams, UDP, CDN batch, domain-front Host header, HTTP/3, carrier fallback with on-disk memory, cover reverse proxy, identity file, SOCKS glue used by the app.

Loopback, jitter off, `mixed` padding, 2 MiB one way (this machine, one run):

| Path | Time | Throughput |
| --- | --- | --- |
| nox `h2` handshake | 2 ms | |
| nox `h2` payload | 9 ms | 229 MiB/s |
| raw TLS 1.3 (same host, discard server) | 2 ms | 1278 MiB/s |

So the prototype is about 5–6× heavier than a bare TLS write on loopback. The gap is Noise, HTTP/2, the mux, copies and padding, not the cipher. VLESS-Reality was not run: this environment has no Xray, and Reality’s cost is also dominated by TLS plus a userspace copy. Treat 229 MiB/s as “fast enough on a LAN”, not as a prediction of a home link through TSPU. Re-measure with `go test ./noxproto/ -run TestThroughput -v`.

## Known limitations

1. Undetectable is not on offer. This raises the cost of the current fingerprints; it does not end DPI.
2. uTLS presets rot. HTTP/2 SETTINGS are only approximately Chrome. QUIC is not disguised as a browser.
3. Go’s TLS stack on the server is not nginx and not a borrowed popular site. Own domain + real certificate is the honest deployment. Shadowing a third party’s handshake (the way Reality does) is not implemented; that approach is already being fingerprinted, which is why this design terminates a real certificate instead.
4. One shared password per server. Anyone with the subscription can connect. Per-user keys are future work.
5. Head-of-line blocking across streams on one connection.
6. CDN mode is bursty and periodic. It is a fallback.
7. Domain fronting is a switch, not a promise that a CDN will allow it.
8. Padding costs bandwidth. Jitter costs latency and throughput.
9. The composition (cookie, frames, mux) has tests but has not had an independent cryptographic review. The primitives are standard; the way they are glued together is new and may have bugs.
10. Active probing resistance equals “looks like whatever you serve”. A generic page on a famous name fails a human or a content check.

## What still has to be tried in Russia

- Direct `h2` to a VPS with a real Let’s Encrypt name that is not already on a VPN list.
- The same with `profile=video` and with `profile=browse`, from mobile data and from home Wi-Fi, because TSPU rules differ.
- `h3` only as a second choice, and only after capturing a QUIC handshake to see if the Initial is classified.
- A CDN in front (`cdn` carrier) using a domain the CDN already serves. Confirm the CDN does not gzip the body (`Cache-Control: no-transform` is set; verify it).
- `front` only on a CDN you have checked still forwards a foreign Host.
- Leave a session up for hours. Long flows are sometimes cut even when the handshake passed.
- Confirm clocks: a phone with the wrong time will fail the 120-second check.
- After a block, confirm the app switches carrier and, with автопереключение, switches server, and that the next connect on that network tries the winner first.

---

## По-русски, коротко

Протокол не прячет «магический шифр». Снаружи это обычный HTTPS. Ключ клиента спрятан в cookie внутри TLS. Кто стучится без ключа, получает сайт, а не обрыв. Несколько потоков сидят в одном долгом соединении. Размер пакетов прыгает, чтобы не было одной и той же длины.

Сервер ставится скриптом `scripts/install-nox-server.sh` рядом с xray, на свой порт, со своим сертификатом. Ссылку `noxp://...` кладут в подписку. В приложении сервер называется NOX. Автопереключение включает запасной переход на старые протоколы. Какой канал сработал в этой сети, клиент запоминает сам.

Пока это прототип. Его обязательно надо гонять с телефона в России на мобильном интернете и на домашнем Wi-Fi. Без этого нельзя сказать, что TSPU его не видит.
