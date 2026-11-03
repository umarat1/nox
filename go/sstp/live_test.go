package sstp

import (
	"context"
	"net"
	"net/url"
	"os"
	"strconv"
	"testing"
	"time"
)

// NOX_SSTP_URL=sstp://user:pass@host:port?sni=... go test -run Live -v
func TestLiveDial(t *testing.T) {
	raw := os.Getenv("NOX_SSTP_URL")
	if raw == "" {
		t.Skip("NOX_SSTP_URL not set")
	}
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	pw, _ := u.User.Password()
	port := 443
	if p := u.Port(); p != "" {
		if n, err := strconv.Atoi(p); err == nil {
			port = n
		}
	}
	sni := u.Query().Get("sni")
	if sni == "" {
		sni = u.Hostname()
	}
	// Resolve via DoH so we skip the box's fake-IP DNS.
	ip := dohA(u.Hostname())
	if ip == "" {
		t.Fatal("no DNS")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	sess, err := Dial(ctx, Config{
		Server: u.Hostname(), Addr: ip, Port: port, User: u.User.Username(), Password: pw, SNI: sni,
		Logf: t.Logf,
		Dial: (&net.Dialer{}).DialContext,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer sess.Close()
	t.Logf("local=%s peer=%s dns=%v mtu=%d auth=%s", sess.LocalIP, sess.PeerIP, sess.DNS, sess.MTU, sess.Auth)
	if sess.LocalIP == nil || sess.LocalIP.IsUnspecified() {
		t.Fatal("no local IP")
	}
}

func dohA(host string) string {
	// tiny helper: use https://1.1.1.1/dns-query
	return lookupDoH(host)
}
