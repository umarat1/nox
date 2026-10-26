package engine

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"runtime"
	"strings"
	"sync"
	"time"
)

// PlatformResolve is the OS resolver (Android: ConnectivityManager on a non-VPN
// network). Nil on desktop, where the cgo resolver is tried instead.
var PlatformResolve func(host string) []net.IP

// publicDNS are queried by IP. UDP dial to a dead carrier resolver succeeds, so a
// query timeout — not a dial error — is what moves on to the next server.
var publicDNS = []string{"1.1.1.1:53", "8.8.8.8:53", "77.88.8.8:53"}

type dohTarget struct {
	ip, sni, path string
}

// DoH speaks to the resolver by IP. SNI is the name on the certificate so
// verification stays on; the HTTP client never looks the name up itself.
var dohTargets = []dohTarget{
	{"1.1.1.1", "cloudflare-dns.com", "/dns-query"},
	{"8.8.8.8", "dns.google", "/dns-query"},
	{"77.88.8.8", "common.dot.dns.yandex.net", "/dns-query"},
}

const (
	dnsUDPWait = 900 * time.Millisecond
	dnsTCPWait = 1200 * time.Millisecond
	dohWait    = 2500 * time.Millisecond
	sysWait    = 2 * time.Second
)

// InstallPublicResolver replaces the process resolver. Go's pure resolver has no
// /etc/resolv.conf on Android and asks [::1]:53. A UDP dial to a dead resolver
// succeeds, and Go then overwrites any deadline we set, so the fallback has to
// live inside the connection: each server gets its own query deadline, and a
// timeout or any other error moves on to the next server (UDP, then TCP).
func InstallPublicResolver() {
	net.DefaultResolver = &net.Resolver{PreferGo: true, Dial: publicDial}
}

func publicDial(ctx context.Context, network, _ string) (net.Conn, error) {
	r := &rotatingDNS{ctx: ctx, tcpQuery: strings.HasPrefix(network, "tcp")}
	if r.tcpQuery {
		return r, nil
	}
	// UDP queries are datagrams. Go picks that from net.PacketConn; a plain
	// net.Conn would be written as a length-prefixed TCP message.
	return packetDNS{r}, nil
}

type dnsAttempt struct {
	server, network string
	wait            time.Duration
}

// rotatingDNS answers one resolver exchange. The first UDP dial succeeding is
// not success: Read waits only for this attempt's deadline, then resends the
// same query to the next server, over TCP if UDP produced nothing.
type rotatingDNS struct {
	ctx      context.Context
	tcpQuery bool // Go already framed the query with a 2-byte length
	mu       sync.Mutex
	query    []byte
	cur      net.Conn
	step     int
	outer    time.Time
}

func (r *rotatingDNS) attempts() []dnsAttempt {
	if r.tcpQuery {
		out := make([]dnsAttempt, 0, len(publicDNS))
		for _, s := range publicDNS {
			out = append(out, dnsAttempt{s, "tcp", dnsTCPWait})
		}
		return out
	}
	out := make([]dnsAttempt, 0, len(publicDNS)*2)
	for _, s := range publicDNS {
		out = append(out, dnsAttempt{s, "udp", dnsUDPWait}, dnsAttempt{s, "tcp", dnsTCPWait})
	}
	return out
}

func (r *rotatingDNS) Write(b []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.query = append([]byte(nil), b...)
	r.step = 0
	if err := r.sendLocked(); err != nil {
		return 0, err
	}
	return len(b), nil
}

func (r *rotatingDNS) Read(b []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.query) == 0 {
		return 0, errors.New("dns: пустой запрос")
	}
	var last error
	for {
		if r.cur == nil {
			if err := r.sendLocked(); err != nil {
				return 0, err
			}
		}
		n, err := r.readLocked(b)
		if err == nil {
			return n, nil
		}
		last = err
		if r.cur != nil {
			r.cur.Close()
			r.cur = nil
		}
		r.step++
		if r.step >= len(r.attempts()) {
			if last == nil {
				last = errors.New("dns: нет ответа")
			}
			return 0, last
		}
	}
}

func (r *rotatingDNS) sendLocked() error {
	attempts := r.attempts()
	var last error
	for r.step < len(attempts) {
		a := attempts[r.step]
		if r.cur != nil {
			r.cur.Close()
			r.cur = nil
		}
		c, err := (&net.Dialer{Timeout: 2 * time.Second}).DialContext(r.ctx, a.network, a.server)
		if err != nil {
			last = err
			r.step++
			continue
		}
		r.cur = c
		r.arm(a.wait)
		payload := r.query
		if a.network == "tcp" && !r.tcpQuery {
			var ln [2]byte
			binary.BigEndian.PutUint16(ln[:], uint16(len(r.query)))
			payload = append(ln[:], r.query...)
		}
		if _, err := c.Write(payload); err != nil {
			last = err
			c.Close()
			r.cur = nil
			r.step++
			continue
		}
		return nil
	}
	if last == nil {
		last = errors.New("dns dial")
	}
	return last
}

func (r *rotatingDNS) readLocked(b []byte) (int, error) {
	a := r.attempts()[r.step]
	if a.network == "tcp" && !r.tcpQuery {
		var ln [2]byte
		if _, err := io.ReadFull(r.cur, ln[:]); err != nil {
			return 0, err
		}
		n := int(binary.BigEndian.Uint16(ln[:]))
		if n < 12 || n > len(b) {
			return 0, errors.New("dns: плохой ответ")
		}
		if _, err := io.ReadFull(r.cur, b[:n]); err != nil {
			return 0, err
		}
		return n, nil
	}
	return r.cur.Read(b)
}

func (r *rotatingDNS) arm(wait time.Duration) {
	dl := time.Now().Add(wait)
	if !r.outer.IsZero() && r.outer.Before(dl) {
		dl = r.outer
	}
	if r.cur != nil {
		_ = r.cur.SetDeadline(dl)
	}
}

func (r *rotatingDNS) SetDeadline(t time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.outer = t
	return nil
}

func (r *rotatingDNS) SetReadDeadline(t time.Time) error  { return r.SetDeadline(t) }
func (r *rotatingDNS) SetWriteDeadline(t time.Time) error { return r.SetDeadline(t) }

func (r *rotatingDNS) Close() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.cur != nil {
		return r.cur.Close()
	}
	return nil
}

func (r *rotatingDNS) LocalAddr() net.Addr {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.cur != nil {
		return r.cur.LocalAddr()
	}
	return &net.UDPAddr{}
}

func (r *rotatingDNS) RemoteAddr() net.Addr {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.cur != nil {
		return r.cur.RemoteAddr()
	}
	return &net.UDPAddr{}
}

// packetDNS is the UDP dial. ReadFrom/WriteTo make it a net.PacketConn so Go
// sends a datagram query; timeouts still walk UDP then TCP on every server.
type packetDNS struct{ *rotatingDNS }

func (p packetDNS) ReadFrom(b []byte) (int, net.Addr, error) {
	n, err := p.Read(b)
	return n, p.RemoteAddr(), err
}

func (p packetDNS) WriteTo(b []byte, _ net.Addr) (int, error) { return p.Write(b) }

// LookupHost resolves host without reading /etc/resolv.conf. Order: platform
// resolver, DNS-over-HTTPS by IP, then 1.1.1.1 / 8.8.8.8 / 77.88.8.8 over UDP
// and, if that times out, TCP. Fake-IP answers (198.18.0.0/15) are skipped.
func LookupHost(ctx context.Context, host string) (string, error) {
	if ip := net.ParseIP(host); ip != nil {
		return host, nil
	}
	host = strings.TrimSuffix(host, ".")
	dnsCache.Lock()
	if e, ok := dnsCache.m[host]; ok && time.Now().Before(e.exp) {
		dnsCache.Unlock()
		return e.ip, nil
	}
	dnsCache.Unlock()
	ip, err := lookupHost(ctx, host, lookupOpt{})
	if err != nil || ip == "" {
		if err == nil {
			err = fmt.Errorf("не удалось найти %s", host)
		}
		return "", err
	}
	dnsCache.Lock()
	dnsCache.m[host] = dnsEnt{ip, time.Now().Add(5 * time.Minute)}
	dnsCache.Unlock()
	return ip, nil
}

type lookupOpt struct {
	skipSystem bool
	servers    []string
	doh        []dohTarget
	skipDoH    bool
	dial       func(context.Context, string, string) (net.Conn, error)
}

func lookupHost(ctx context.Context, host string, opt lookupOpt) (string, error) {
	if !opt.skipSystem {
		c, cancel := context.WithTimeout(ctx, sysWait)
		ip, err := systemLookup(c, host)
		cancel()
		if err == nil && ip != "" && !fakeIP(ip) {
			return ip, nil
		}
	}
	if !opt.skipDoH {
		targets := opt.doh
		if targets == nil {
			targets = dohTargets
		}
		if ip := raceDoH(ctx, host, targets, opt.dial); ip != "" && !fakeIP(ip) {
			return ip, nil
		}
	}
	servers := opt.servers
	if len(servers) == 0 {
		servers = publicDNS
	}
	var last error
	for _, srv := range servers {
		for _, step := range []struct {
			net  string
			wait time.Duration
		}{{"udp", dnsUDPWait}, {"tcp", dnsTCPWait}} {
			c, cancel := context.WithTimeout(ctx, step.wait)
			ip, err := exchangeDNS(c, step.net, srv, host, opt.dial)
			cancel()
			if err == nil && ip != "" && !fakeIP(ip) {
				return ip, nil
			}
			if err != nil {
				last = err
			}
		}
	}
	if last == nil {
		last = fmt.Errorf("не удалось найти %s", host)
	}
	return "", last
}

func fakeIP(s string) bool {
	ip := net.ParseIP(s)
	return ip != nil && isFakeIP(ip)
}

func systemLookup(ctx context.Context, host string) (string, error) {
	if PlatformResolve != nil {
		ch := make(chan []net.IP, 1)
		go func() { ch <- PlatformResolve(host) }()
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case ips := <-ch:
			if ip := preferIP(ips); ip != "" {
				return ip, nil
			}
		}
	}
	if runtime.GOOS == "android" {
		return "", errors.New("системный резолвер недоступен")
	}
	r := &net.Resolver{PreferGo: false}
	ips, err := r.LookupIP(ctx, "ip", host)
	if err != nil {
		return "", err
	}
	if ip := preferIP(ips); ip != "" {
		return ip, nil
	}
	return "", errors.New("пустой ответ")
}

func preferIP(ips []net.IP) string {
	for _, ip := range ips {
		if ip.To4() != nil && !isFakeIP(ip) {
			return ip.String()
		}
	}
	for _, ip := range ips {
		if !isFakeIP(ip) {
			return ip.String()
		}
	}
	return ""
}

func raceDoH(ctx context.Context, host string, targets []dohTarget, dial func(context.Context, string, string) (net.Conn, error)) string {
	if len(targets) == 0 {
		return ""
	}
	ctx, cancel := context.WithTimeout(ctx, dohWait)
	defer cancel()
	ch := make(chan string, len(targets))
	var wg sync.WaitGroup
	for _, t := range targets {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ip, err := dohQuery(ctx, t, host, dial)
			if err == nil && ip != "" {
				ch <- ip
				cancel()
			}
		}()
	}
	go func() { wg.Wait(); close(ch) }()
	ip, _ := <-ch
	return ip
}

func dohQuery(ctx context.Context, t dohTarget, host string, dial func(context.Context, string, string) (net.Conn, error)) (string, error) {
	q, id := dnsQuestion(host)
	tr := &http.Transport{
		Proxy:               nil,
		TLSHandshakeTimeout: 2 * time.Second,
		DialTLSContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			var c net.Conn
			var err error
			if dial != nil {
				c, err = dial(ctx, "tcp", net.JoinHostPort(t.ip, "443"))
			} else {
				c, err = (&net.Dialer{Timeout: 2 * time.Second}).DialContext(ctx, "tcp", net.JoinHostPort(t.ip, "443"))
			}
			if err != nil {
				return nil, err
			}
			tlsConn := tls.Client(c, &tls.Config{ServerName: t.sni, MinVersion: tls.VersionTLS12})
			if err := tlsConn.HandshakeContext(ctx); err != nil {
				c.Close()
				return nil, err
			}
			return tlsConn, nil
		},
	}
	defer tr.CloseIdleConnections()
	cl := &http.Client{Timeout: dohWait, Transport: tr}
	req, err := http.NewRequestWithContext(ctx, "POST", "https://"+t.sni+t.path, bytes.NewReader(q))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/dns-message")
	req.Header.Set("Accept", "application/dns-message")
	resp, err := cl.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("doh %s", resp.Status)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if err != nil {
		return "", err
	}
	ip := parseA(body, id)
	if ip == "" {
		return "", errors.New("doh: нет A-записи")
	}
	return ip, nil
}

func exchangeDNS(ctx context.Context, network, server, host string, dial func(context.Context, string, string) (net.Conn, error)) (string, error) {
	q, id := dnsQuestion(host)
	if !strings.Contains(server, ":") {
		server = net.JoinHostPort(server, "53")
	}
	var c net.Conn
	var err error
	if dial != nil {
		c, err = dial(ctx, network, server)
	} else {
		c, err = (&net.Dialer{Timeout: 2 * time.Second}).DialContext(ctx, network, server)
	}
	if err != nil {
		return "", err
	}
	defer c.Close()
	deadline, ok := ctx.Deadline()
	if !ok {
		deadline = time.Now().Add(dnsUDPWait)
	}
	_ = c.SetDeadline(deadline)
	var buf []byte
	if strings.HasPrefix(network, "tcp") {
		var ln [2]byte
		binary.BigEndian.PutUint16(ln[:], uint16(len(q)))
		if _, err := c.Write(append(ln[:], q...)); err != nil {
			return "", err
		}
		if _, err := io.ReadFull(c, ln[:]); err != nil {
			return "", err
		}
		n := int(binary.BigEndian.Uint16(ln[:]))
		if n < 12 || n > 4096 {
			return "", errors.New("dns: плохой ответ")
		}
		buf = make([]byte, n)
		if _, err := io.ReadFull(c, buf); err != nil {
			return "", err
		}
	} else {
		if _, err := c.Write(q); err != nil {
			return "", err
		}
		buf = make([]byte, 1500)
		n, err := c.Read(buf)
		if err != nil {
			return "", err
		}
		buf = buf[:n]
	}
	ip := parseA(buf, id)
	if ip == "" {
		return "", errors.New("dns: нет A-записи")
	}
	return ip, nil
}

func dnsQuestion(host string) ([]byte, [2]byte) {
	var id [2]byte
	_, _ = rand.Read(id[:])
	q := []byte{id[0], id[1], 1, 0, 0, 1, 0, 0, 0, 0, 0, 0}
	for _, l := range splitDots(host) {
		if len(l) == 0 || len(l) > 63 {
			return q, id
		}
		q = append(q, byte(len(l)))
		q = append(q, l...)
	}
	q = append(q, 0, 0, 1, 0, 1) // A IN
	return q, id
}

// dialResolved connects to addr. A hostname is resolved here, then the TCP
// connection goes to that IP. TLS still checks the original name: net/http sets
// ServerName from the URL, not from the dialed address.
func dialResolved(ctx context.Context, network, addr string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, err
	}
	d := &net.Dialer{Timeout: 10 * time.Second}
	if net.ParseIP(host) != nil {
		return d.DialContext(ctx, network, addr)
	}
	ip, err := LookupHost(ctx, host)
	if err != nil {
		return nil, err
	}
	return d.DialContext(ctx, network, net.JoinHostPort(ip, port))
}

// friendlyNetErr is what the refresh toast shows. The raw error carries the
// subscription URL (and its token) plus a multi-line resolver trace.
func friendlyNetErr(err error) error {
	if err == nil {
		return nil
	}
	s := err.Error()
	low := strings.ToLower(s)
	if strings.Contains(low, "lookup ") || strings.Contains(low, "no such host") ||
		strings.Contains(low, "i/o timeout") || strings.Contains(s, ":53") ||
		strings.Contains(low, "не удалось найти") {
		return errors.New("не удалось найти адрес сервера подписки. Список серверов не изменён")
	}
	if i := strings.Index(s, "\": "); i >= 0 && strings.Contains(s[:i], "Get \"") {
		s = s[i+3:]
	}
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > 160 {
		s = s[:160] + "…"
	}
	return errors.New(s)
}
