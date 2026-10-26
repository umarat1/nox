package extra

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net"
	"strconv"
	"testing"
	"time"

	"nox/noxproto"
)

func TestNoxSocksLoopback(t *testing.T) {
	id, err := noxproto.NewIdentity()
	if err != nil {
		t.Fatal(err)
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
		DNSNames:     []string{"nox.test"},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert := tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	addr := "127.0.0.1:" + strconv.Itoa(port)
	srv, err := noxproto.Listen(addr, "", cert, noxproto.ServerConfig{Identity: id, Jitter: 0, Hold: 20 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { srv.Close() })

	echo, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { echo.Close() })
	go func() {
		for {
			c, err := echo.Accept()
			if err != nil {
				return
			}
			go func() { defer c.Close(); _, _ = io.Copy(c, c) }()
		}
	}()

	raw, err := json.Marshal(map[string]any{
		"kind": "nox",
		"cfg": map[string]any{
			"pub":       noxproto.PubString(id.Public),
			"pass":      id.Password,
			"server":    "127.0.0.1",
			"port":      port,
			"sni":       "nox.test",
			"authority": "nox.test",
			"carrier":   "h2",
			"fp":        "chrome",
			"insecure":  true,
			"jitter":    0,
			"network":   "socks-test",
			"profile":   "browse",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	local, err := Start(raw)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(local.Stop)

	eh, ep, _ := net.SplitHostPort(echo.Addr().String())
	en, _ := strconv.Atoi(ep)
	c, err := socksDial(local.Port, eh, uint16(en))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.Write([]byte("socks")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 5)
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatal(err)
	}
	if string(buf) != "socks" {
		t.Fatalf("echo %q", buf)
	}
}

func socksDial(local int, host string, port uint16) (net.Conn, error) {
	c, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(local), 3*time.Second)
	if err != nil {
		return nil, err
	}
	if _, err := c.Write([]byte{5, 1, 0}); err != nil {
		c.Close()
		return nil, err
	}
	buf := make([]byte, 2)
	if _, err := io.ReadFull(c, buf); err != nil || buf[0] != 5 || buf[1] != 0 {
		c.Close()
		return nil, err
	}
	req := []byte{5, 1, 0, 3, byte(len(host))}
	req = append(req, host...)
	req = append(req, byte(port>>8), byte(port))
	if _, err := c.Write(req); err != nil {
		c.Close()
		return nil, err
	}
	hdr := make([]byte, 4)
	if _, err := io.ReadFull(c, hdr); err != nil {
		c.Close()
		return nil, err
	}
	if hdr[1] != 0 {
		c.Close()
		return nil, fmt.Errorf("socks: отказ %d", hdr[1])
	}
	switch hdr[3] {
	case 1:
		_, _ = io.ReadFull(c, make([]byte, 6))
	case 3:
		var n [1]byte
		_, _ = io.ReadFull(c, n[:])
		_, _ = io.ReadFull(c, make([]byte, int(n[0])+2))
	case 4:
		_, _ = io.ReadFull(c, make([]byte, 18))
	}
	return c, nil
}
