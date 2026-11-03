package engine

import (
	"net"
	"testing"

	"nox/core"
)

func TestParseA(t *testing.T) {
	id := [2]byte{0x12, 0x34}
	// header, 1 question, 2 answers (CNAME then A) with name compression
	b := []byte{0x12, 0x34, 0x81, 0x80, 0, 1, 0, 2, 0, 0, 0, 0,
		3, 'w', 'w', 'w', 1, 'x', 0, 0, 1, 0, 1,
		0xC0, 12, 0, 5, 0, 1, 0, 0, 0, 60, 0, 2, 0xC0, 12,
		0xC0, 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 31, 76, 249, 120}
	if ip := parseA(b, id); ip != "31.76.249.120" {
		t.Fatal(ip)
	}
	if parseA(b, [2]byte{0, 0}) != "" {
		t.Fatal("id mismatch accepted")
	}
	if !isFakeIP(net.ParseIP("198.18.0.5")) || isFakeIP(net.ParseIP("8.8.8.8")) {
		t.Fatal("fakeip")
	}
}

func TestTCPPingDirect(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Skip(err)
	}
	defer l.Close()
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			c.Close()
		}
	}()
	p := pingNet{}
	if ms := p.tcpPing("127.0.0.1", l.Addr().(*net.TCPAddr).Port); ms < 1 {
		t.Fatal(ms)
	}
	if ms := p.tcpPing("127.0.0.1", 1); ms != -1 {
		t.Fatal("closed port", ms)
	}
}

func TestNextServer(t *testing.T) {
	all := []core.Server{
		{ID: "1", Name: "🇩🇪 Германия", Type: "VLESS", Host: "a", Port: 1, Ping: 50},
		{ID: "2", Name: "🇩🇪 Германия", Type: "Trojan", Host: "b", Port: 2, Ping: 300},
		{ID: "3", Name: "🇳🇱 Нидерланды", Type: "VLESS", Host: "c", Port: 3, Ping: 40},
		{ID: "4", Name: "🇫🇮 Финляндия", Type: "VLESS", Host: "d", Port: 4, Ping: -1},
	}
	if n := nextServer(all, all[0]); n == nil || n.ID != "2" {
		t.Fatalf("same country other protocol first: %+v", n)
	}
	if n := nextServer(all, all[1]); n == nil || n.ID != "1" {
		t.Fatalf("%+v", n)
	}
	if n := nextServer(all[2:], all[2]); n != nil {
		t.Fatalf("dead must be skipped: %+v", n)
	}
	if regionOf("🇬🇧 Лондон") != "GB" || regionOf("London") != "" {
		t.Fatal("region")
	}
}
