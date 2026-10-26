package engine

import (
	"context"
	"encoding/binary"
	"net"
	"strings"
	"testing"
	"time"
)

func TestLookupFallsThroughWhenUDPDialSucceedsButQueryTimesOut(t *testing.T) {
	// A UDP socket that never answers: Dial succeeds, the query must time out,
	// and the next server (which does answer) must be used. This is the Android
	// failure mode — there is no /etc/resolv.conf involved.
	black, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer black.Close()
	good := serveA(t, net.ParseIP("9.9.9.9"))

	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()
	ip, err := lookupHost(ctx, "panel.example", lookupOpt{
		skipSystem: true,
		skipDoH:    true,
		servers:    []string{black.LocalAddr().String(), good},
	})
	if err != nil {
		t.Fatal(err)
	}
	if ip != "9.9.9.9" {
		t.Fatalf("ip %s", ip)
	}
}

func TestTCPDNSAnswersWhenUDPWouldFail(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				var ln2 [2]byte
				if _, err := c.Read(ln2[:]); err != nil {
					return
				}
				n := int(binary.BigEndian.Uint16(ln2[:]))
				q := make([]byte, n)
				if _, err := c.Read(q); err != nil {
					return
				}
				body := answerA(q, net.ParseIP("8.8.4.4").To4())
				var out [2]byte
				binary.BigEndian.PutUint16(out[:], uint16(len(body)))
				_, _ = c.Write(append(out[:], body...))
			}()
		}
	}()
	// Blackhole UDP first so the TCP step of that server, then this TCP listener, runs.
	// Point both UDP and TCP at the TCP listener by using only that address: UDP dial
	// fails (nothing on UDP), TCP then succeeds.
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	ip, err := lookupHost(ctx, "panel.example", lookupOpt{
		skipSystem: true,
		skipDoH:    true,
		servers:    []string{ln.Addr().String()},
	})
	if err != nil {
		t.Fatal(err)
	}
	if ip != "8.8.4.4" {
		t.Fatalf("ip %s", ip)
	}
}

func TestPublicDialFallsThroughWhenQueryTimesOut(t *testing.T) {
	// Same failure as Android: UDP dial succeeds, nobody answers, and Go has
	// already set a 5s deadline on the conn. The next server must still be used.
	black, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer black.Close()
	good := serveA(t, net.ParseIP("9.9.9.9"))
	old := publicDNS
	publicDNS = []string{black.LocalAddr().String(), good}
	t.Cleanup(func() { publicDNS = old })

	c, err := publicDial(context.Background(), "udp", "[::1]:53")
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if err := c.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		t.Fatal(err)
	}
	q, id := dnsQuestion("panel.example")
	if _, err := c.Write(q); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 1500)
	start := time.Now()
	n, err := c.Read(buf)
	if err != nil {
		t.Fatal(err)
	}
	if time.Since(start) > 3*time.Second {
		t.Fatalf("query waited %s, deadline was not per server", time.Since(start))
	}
	if ip := parseA(buf[:n], id); ip != "9.9.9.9" {
		t.Fatalf("ip %s", ip)
	}
}

func TestPublicDialUsesTCPWhenUDPIsSilent(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				var ln2 [2]byte
				if _, err := c.Read(ln2[:]); err != nil {
					return
				}
				n := int(binary.BigEndian.Uint16(ln2[:]))
				q := make([]byte, n)
				if _, err := c.Read(q); err != nil {
					return
				}
				body := answerA(q, net.ParseIP("8.8.4.4").To4())
				var out [2]byte
				binary.BigEndian.PutUint16(out[:], uint16(len(body)))
				_, _ = c.Write(append(out[:], body...))
			}()
		}
	}()
	old := publicDNS
	publicDNS = []string{ln.Addr().String()}
	t.Cleanup(func() { publicDNS = old })

	c, err := publicDial(context.Background(), "udp", "[::1]:53")
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	q, id := dnsQuestion("panel.example")
	if _, err := c.Write(q); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 1500)
	n, err := c.Read(buf)
	if err != nil {
		t.Fatal(err)
	}
	if ip := parseA(buf[:n], id); ip != "8.8.4.4" {
		t.Fatalf("ip %s", ip)
	}
}

func TestFriendlyNetErrHidesURL(t *testing.T) {
	err := friendlyNetErr(context.DeadlineExceeded)
	// deadline text is short; the DNS-shaped error must drop the token URL
	msg := friendlyNetErr(errString("Get \"https://rus1.example:4443/api/sub/SECRET?nocache=1\": dial tcp: lookup rus1.example on [::1]:53: read udp 10.0.0.2:1->10.9.9.9:53: i/o timeout"))
	if strings.Contains(msg.Error(), "SECRET") || strings.Contains(msg.Error(), "https://") {
		t.Fatal(msg)
	}
	if !strings.Contains(msg.Error(), "не изменён") {
		t.Fatal(msg)
	}
	_ = err
}

type errString string

func (e errString) Error() string { return string(e) }

func serveA(t *testing.T, ip net.IP) string {
	t.Helper()
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
			_, _ = pc.WriteTo(answerA(buf[:n], ip.To4()), addr)
		}
	}()
	return pc.LocalAddr().String()
}

func answerA(q []byte, ip net.IP) []byte {
	resp := append([]byte{}, q...)
	if len(resp) < 12 {
		return resp
	}
	resp[2], resp[3] = 0x81, 0x80
	binary.BigEndian.PutUint16(resp[6:8], 1)
	resp = append(resp, 0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4)
	return append(resp, ip...)
}
