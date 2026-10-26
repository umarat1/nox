package noxproto

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"io"
	"math/big"
	"net"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

func testCert(t *testing.T) tls.Certificate {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
		DNSNames:     []string{"nox.test"},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
}

func testIdentity(t *testing.T) Identity {
	t.Helper()
	id, err := NewIdentity()
	if err != nil {
		t.Fatal(err)
	}
	return id
}

func startServer(t *testing.T, id Identity, udp bool, hold time.Duration) *Server {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	addr := "127.0.0.1:" + strconv.Itoa(port)
	udpAddr := ""
	if udp {
		udpAddr = addr
	}
	s, err := Listen(addr, udpAddr, testCert(t), ServerConfig{
		Identity: id,
		Profile:  ProfileMixed,
		Jitter:   0,
		Hold:     hold,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	time.Sleep(30 * time.Millisecond)
	return s
}

func clientCfg(s *Server, id Identity, carriers []string) Config {
	return Config{
		Addr:        s.Addr(),
		H3Addr:      s.UDPAddr(),
		SNI:         "nox.test",
		Authority:   "nox.test",
		Pub:         id.Public,
		Password:    id.Password,
		Carriers:    carriers,
		Profile:     ProfileMixed,
		Fingerprint: "chrome",
		Insecure:    true,
		JitterSet:   true,
		Jitter:      0,
		Poll:        25 * time.Millisecond,
		Timeout:     4 * time.Second,
		Network:     "test",
	}
}

func echoTCP(t *testing.T) (string, uint16) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				_, _ = io.Copy(c, c)
			}()
		}
	}()
	h, p, _ := net.SplitHostPort(ln.Addr().String())
	n, _ := strconv.Atoi(p)
	return h, uint16(n)
}

func TestNoiseRoundTripAndReplay(t *testing.T) {
	id := testIdentity(t)
	msg1, hs, err := clientHello(Identity{Password: id.Password}, id.Public, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	rep := newReplay()
	msg2, ss, sr, err := serverAccept(id, msg1, time.Now(), rep)
	if err != nil {
		t.Fatal(err)
	}
	cs, cr, err := clientFinish(hs, msg2)
	if err != nil {
		t.Fatal(err)
	}
	ct, err := cs.Encrypt(nil, nil, []byte("ping"))
	if err != nil {
		t.Fatal(err)
	}
	pt, err := sr.Decrypt(nil, nil, ct)
	if err != nil {
		t.Fatal(err)
	}
	if string(pt) != "ping" {
		t.Fatalf("server decrypted %q", pt)
	}
	ct, err = ss.Encrypt(nil, nil, []byte("pong"))
	if err != nil {
		t.Fatal(err)
	}
	pt, err = cr.Decrypt(nil, nil, ct)
	if err != nil {
		t.Fatal(err)
	}
	if string(pt) != "pong" {
		t.Fatalf("client decrypted %q", pt)
	}
	if _, _, _, err := serverAccept(id, msg1, time.Now(), rep); err == nil {
		t.Fatal("replay was accepted")
	}
	old := time.Now().Add(-10 * time.Minute)
	msgOld, _, err := clientHello(Identity{Password: id.Password}, id.Public, old)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, _, err := serverAccept(id, msgOld, time.Now(), newReplay()); err == nil {
		t.Fatal("stale timestamp was accepted")
	}
	bad := testIdentity(t)
	msgBad, _, err := clientHello(Identity{Password: "nope"}, id.Public, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if _, _, _, err := serverAccept(id, msgBad, time.Now(), newReplay()); err == nil {
		t.Fatal("wrong password was accepted")
	}
	_ = bad
}

func TestFramePadding(t *testing.T) {
	allowed := map[int]bool{128: true, 256: true, 384: true, 512: true, 700: true, 1024: true, 1400: true}
	for i := 0; i < 40; i++ {
		n := sampleLen(ProfileBrowse)
		if !allowed[n] {
			t.Fatalf("browse size %d not in profile", n)
		}
		f := encodeFrame(frame{typ: framePing}, n)
		if len(f) != n {
			t.Fatalf("padded to %d want %d", len(f), n)
		}
		got, err := decodeFrame(f)
		if err != nil || got.typ != framePing {
			t.Fatal(err, got.typ)
		}
	}
	big := encodeFrame(frame{typ: frameData, id: 7, data: bytesOf(300)}, 128)
	if len(big) < 307 {
		t.Fatalf("payload should expand the frame, len %d", len(big))
	}
	got, err := decodeFrame(big)
	if err != nil || got.id != 7 || len(got.data) != 300 {
		t.Fatalf("decode %+v %v", got, err)
	}
}

func bytesOf(n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte(i)
	}
	return b
}

func TestDecoyAndBadAuth(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, false, 0)
	cl := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}}
	res, err := cl.Get("https://" + s.Addr() + "/")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != 200 || !strings.Contains(string(body), "Field notes") {
		t.Fatalf("decoy status %d body %q", res.StatusCode, body)
	}
	req, _ := http.NewRequest(http.MethodPost, "https://"+s.Addr()+"/api/v1/events", strings.NewReader("hello"))
	req.Header.Set("Cookie", "sid="+strings.Repeat("a", 40))
	res, err = cl.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ = io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != 200 || !strings.Contains(string(body), "Field notes") {
		t.Fatalf("bad auth status %d body %q", res.StatusCode, body)
	}
	d := NewDialerConfig(clientCfg(s, Identity{Public: id.Public, Password: "wrong", Private: id.Private}, []string{CarrierH2}))
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	if _, err := d.Dial(ctx, "tcp", "127.0.0.1", 1); err == nil {
		t.Fatal("wrong password dialed")
	}
}

func TestLoopbackH2(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, false, 0)
	d := NewDialerConfig(clientCfg(s, id, []string{CarrierH2}))
	t.Cleanup(func() { d.Close() })
	host, port := echoTCP(t)
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	c, err := d.Dial(ctx, "tcp", host, port)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.Write([]byte("hello-nox")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 9)
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatal(err)
	}
	if string(buf) != "hello-nox" {
		t.Fatalf("echo %q", buf)
	}
}

func TestDialSurvivesCallerCancel(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, false, 0)
	d := NewDialerConfig(clientCfg(s, id, []string{CarrierH2}))
	t.Cleanup(func() { d.Close() })
	host, port := echoTCP(t)
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	c, err := d.Dial(ctx, "tcp", host, port)
	cancel()
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.Write([]byte("still-up")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 8)
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatal(err)
	}
	if string(buf) != "still-up" {
		t.Fatalf("echo %q", buf)
	}
}

func TestMultiplex(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, false, 0)
	d := NewDialerConfig(clientCfg(s, id, []string{CarrierH2}))
	t.Cleanup(func() { d.Close() })
	host, port := echoTCP(t)
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	a, err := d.Dial(ctx, "tcp", host, port)
	if err != nil {
		t.Fatal(err)
	}
	defer a.Close()
	b, err := d.Dial(ctx, "tcp", host, port)
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close()
	_ = a.SetDeadline(time.Now().Add(5 * time.Second))
	_ = b.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := a.Write([]byte("AAA")); err != nil {
		t.Fatal(err)
	}
	if _, err := b.Write([]byte("BBB")); err != nil {
		t.Fatal(err)
	}
	got := func(c net.Conn, n int) string {
		buf := make([]byte, n)
		if _, err := io.ReadFull(c, buf); err != nil {
			t.Fatal(err)
		}
		return string(buf)
	}
	if got(a, 3) != "AAA" || got(b, 3) != "BBB" {
		t.Fatal("streams crossed or lost data")
	}
}

func TestUDP(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, false, 0)
	d := NewDialerConfig(clientCfg(s, id, []string{CarrierH2}))
	t.Cleanup(func() { d.Close() })
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { pc.Close() })
	go func() {
		buf := make([]byte, 1500)
		for {
			n, addr, err := pc.ReadFrom(buf)
			if err != nil {
				return
			}
			_, _ = pc.WriteTo(buf[:n], addr)
		}
	}()
	h, p, _ := net.SplitHostPort(pc.LocalAddr().String())
	n, _ := strconv.Atoi(p)
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	c, err := d.Dial(ctx, "udp", h, uint16(n))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.Write([]byte("udp")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 8)
	rn, err := c.Read(buf)
	if err != nil {
		t.Fatal(err)
	}
	if string(buf[:rn]) != "udp" {
		t.Fatalf("udp echo %q", buf[:rn])
	}
}

func TestCDNAndFront(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, false, 40*time.Millisecond)
	cfg := clientCfg(s, id, []string{CarrierCDN})
	d := NewDialerConfig(cfg)
	t.Cleanup(func() { d.Close() })
	host, port := echoTCP(t)
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	c, err := d.Dial(ctx, "tcp", host, port)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(6 * time.Second))
	if _, err := io.WriteString(c, "cdn"); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 3)
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatal(err)
	}
	if string(buf) != "cdn" {
		t.Fatalf("cdn echo %q", buf)
	}
	d.Close()

	cfg = clientCfg(s, id, []string{CarrierFront})
	cfg.Authority = "origin.example"
	d2 := NewDialerConfig(cfg)
	t.Cleanup(func() { d2.Close() })
	c2, err := d2.Dial(ctx, "tcp", host, port)
	if err != nil {
		t.Fatal(err)
	}
	defer c2.Close()
	if _, err := io.WriteString(c2, "fr"); err != nil {
		t.Fatal(err)
	}
	buf = make([]byte, 2)
	_ = c2.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.ReadFull(c2, buf); err != nil {
		t.Fatal(err)
	}
	if s.SeenHost() != "origin.example" {
		t.Fatalf("front host %q", s.SeenHost())
	}
}

func TestH3(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, true, 0)
	if s.UDPAddr() == "" {
		t.Fatal("no udp")
	}
	d := NewDialerConfig(clientCfg(s, id, []string{CarrierH3}))
	t.Cleanup(func() { d.Close() })
	host, port := echoTCP(t)
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	c, err := d.Dial(ctx, "tcp", host, port)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.Write([]byte("h3")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 2)
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatal(err)
	}
	if string(buf) != "h3" {
		t.Fatalf("h3 echo %q", buf)
	}
}

func TestCarrierFallbackMemory(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, false, 0)
	dir := t.TempDir()
	cfg := clientCfg(s, id, []string{CarrierH3, CarrierH2})
	cfg.H3Addr = "127.0.0.1:1"
	cfg.Timeout = 400 * time.Millisecond
	cfg.MemFile = dir + "/mem.json"
	cfg.Network = "lab"
	d := NewDialerConfig(cfg)
	t.Cleanup(func() { d.Close() })
	host, port := echoTCP(t)
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	c, err := d.Dial(ctx, "tcp", host, port)
	if err != nil {
		t.Fatal(err)
	}
	c.Close()
	order := OpenMemory(cfg.MemFile).Order("lab", []string{CarrierH3, CarrierH2})
	if len(order) < 2 || order[0] != CarrierH2 {
		t.Fatalf("memory order %v", order)
	}
}

func TestCoverProxy(t *testing.T) {
	cover := http.Server{Addr: "127.0.0.1:0", Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Cookie") != "" {
			http.Error(w, "cookie leaked", 500)
			return
		}
		_, _ = io.WriteString(w, "cover-site")
	})}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go cover.Serve(ln)
	t.Cleanup(func() { cover.Close() })

	id := testIdentity(t)
	tcp, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := tcp.Addr().(*net.TCPAddr).Port
	tcp.Close()
	s, err := Listen("127.0.0.1:"+strconv.Itoa(port), "", testCert(t), ServerConfig{
		Identity: id,
		Cover:    "http://" + ln.Addr().String(),
		Jitter:   0,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	time.Sleep(30 * time.Millisecond)
	cl := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}}
	req, _ := http.NewRequest(http.MethodGet, "https://"+s.Addr()+"/", nil)
	req.Header.Set("Cookie", "sid=not-a-tunnel")
	res, err := cl.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if !strings.Contains(string(body), "cover-site") {
		t.Fatalf("cover body %q", body)
	}
}

func TestKeyFile(t *testing.T) {
	id := testIdentity(t)
	path := t.TempDir() + "/id"
	if err := SaveIdentity(path, id); err != nil {
		t.Fatal(err)
	}
	got, err := LoadIdentity(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got.Public) != string(id.Public) || got.Password != id.Password || string(got.Private) != string(id.Private) {
		t.Fatal("identity roundtrip")
	}
	if _, err := ParsePub(PubString(id.Public)); err != nil {
		t.Fatal(err)
	}
}

func TestThroughput(t *testing.T) {
	id := testIdentity(t)
	s := startServer(t, id, false, 0)
	d := NewDialerConfig(clientCfg(s, id, []string{CarrierH2}))
	t.Cleanup(func() { d.Close() })
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	const n = 2 << 20
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		buf := make([]byte, 32*1024)
		_, _ = io.CopyBuffer(io.Discard, c, buf)
	}()
	h, p, _ := net.SplitHostPort(ln.Addr().String())
	pn, _ := strconv.Atoi(p)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	t0 := time.Now()
	c, err := d.Dial(ctx, "tcp", h, uint16(pn))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	hs := time.Since(t0)
	payload := make([]byte, 32*1024)
	_, _ = rand.Read(payload)
	start := time.Now()
	left := n
	for left > 0 {
		k := len(payload)
		if k > left {
			k = left
		}
		if _, err := c.Write(payload[:k]); err != nil {
			t.Fatal(err)
		}
		left -= k
	}
	dt := time.Since(start)
	mbps := float64(n) / dt.Seconds() / (1 << 20)
	t.Logf("nox h2: handshake %s, %d bytes in %s (%.1f MiB/s)", hs.Round(time.Millisecond), n, dt.Round(time.Millisecond), mbps)

	cert := testCert(t)
	rawLn, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS13})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { rawLn.Close() })
	go func() {
		c, err := rawLn.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		_, _ = io.Copy(io.Discard, c)
	}()
	raw, err := tls.Dial("tcp", rawLn.Addr().String(), &tls.Config{InsecureSkipVerify: true, MinVersion: tls.VersionTLS13})
	if err != nil {
		t.Fatal(err)
	}
	defer raw.Close()
	start = time.Now()
	left = n
	for left > 0 {
		k := len(payload)
		if k > left {
			k = left
		}
		if _, err := raw.Write(payload[:k]); err != nil {
			t.Fatal(err)
		}
		left -= k
	}
	dt = time.Since(start)
	t.Logf("raw tls: %d bytes in %s (%.1f MiB/s)", n, dt.Round(time.Millisecond), float64(n)/dt.Seconds()/(1<<20))
}
