package engine

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"net"
	"runtime"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

// pingNet: how ping sockets reach the network. When a tunnel is up, sockets are pinned to the
// physical NIC so TCP ping measures the direct route to the server and never goes through
// (or disturbs) the VPN. When disconnected, the normal route is used.
type pingNet struct {
	nic   physNIC
	bound bool
}

func (a *App) pingNetwork() pingNet {
	a.mu.Lock()
	up := a.status != "disconnected"
	hint := a.physHint
	a.mu.Unlock()
	if !up {
		return pingNet{}
	}
	n, ok := findPhysNIC(hint)
	if !ok {
		if runtime.GOOS == "windows" {
			a.log("пинг: физический адаптер не найден, TCP-пинг пойдёт по таблице маршрутов")
		}
		return pingNet{}
	}
	if n.Name != lastNICLogged {
		lastNICLogged = n.Name
		a.log("сеть: физический адаптер «" + n.Name + "»")
	}
	return pingNet{nic: n, bound: true}
}

var lastNICLogged string

func (p pingNet) dialer(t time.Duration) *net.Dialer {
	d := &net.Dialer{Timeout: t}
	if p.bound {
		d.Control = bindControl(p.nic)
	} else if vpnCaptures() {
		d.Control = protectControl
	}
	return d
}

// boundDNSDead is reset at the start of every ping run.
var boundDNSDead int32

var dnsCache = struct {
	sync.Mutex
	m map[string]dnsEnt
}{m: map[string]dnsEnt{}}

type dnsEnt struct {
	ip  string
	exp time.Time
}

func isFakeIP(ip net.IP) bool {
	v4 := ip.To4()
	return v4 != nil && v4[0] == 198 && (v4[1] == 18 || v4[1] == 19)
}

// resolveDirect: public DNS (77.88.8.8, 1.1.1.1) straight over the physical route first,
// then the system resolver; fake-IP answers (198.18/15, left by TUN clients in the OS
// cache) are skipped. Used for the disconnected URL test, where sing-box's "local" DNS
// would otherwise get whatever the OS resolver hands out.
func (p pingNet) resolveDirect(host string) string {
	return p.lookup(host)
}

// pinIP replaces a domain "server" of a sing-box outbound with a resolved IP for the ping
// instance, keeping the domain where the protocol needs it (TLS SNI, WS Host header).
func pinIP(ob map[string]any, pn pingNet) {
	host, _ := ob["server"].(string)
	if host == "" || net.ParseIP(host) != nil {
		return
	}
	ip := pn.resolveDirect(host)
	if ip == "" {
		return
	}
	ob["server"] = ip
	if tls, ok := ob["tls"].(map[string]any); ok && tls["enabled"] == true {
		if sn, _ := tls["server_name"].(string); sn == "" {
			tls["server_name"] = host
		}
	}
	if tr, ok := ob["transport"].(map[string]any); ok {
		switch tr["type"] {
		case "ws", "httpupgrade":
			if h, _ := tr["host"].(string); h == "" {
				hd, _ := tr["headers"].(map[string]any)
				if hd == nil {
					hd = map[string]any{}
				}
				if _, ok := hd["Host"]; !ok {
					if tr["type"] == "ws" {
						hd["Host"] = host
						tr["headers"] = hd
					} else {
						tr["host"] = host
					}
				}
			}
		case "http":
			if hs, _ := tr["host"].([]any); len(hs) == 0 {
				tr["host"] = []any{host}
			}
		}
	}
}

// resolve returns one IP for host. Bound mode first asks public DNS directly over the
// physical NIC (no VPN round-trip), then falls back to the system resolver.
func (p pingNet) lookup(host string) string {
	if ip := net.ParseIP(host); ip != nil {
		return host
	}
	dnsCache.Lock()
	if e, ok := dnsCache.m[host]; ok && time.Now().Before(e.exp) {
		dnsCache.Unlock()
		return e.ip
	}
	dnsCache.Unlock()
	wait := 8 * time.Second
	if vpnCaptures() {
		wait = 3 * time.Second
	}
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	opt := lookupOpt{}
	if p.bound || vpnCaptures() {
		// The OS resolver follows the tunnel. Ask public DNS on a protected
		// socket (or the physical NIC, on Windows) instead of waiting it out.
		opt.skipSystem = true
		opt.dial = func(ctx context.Context, network, addr string) (net.Conn, error) {
			return p.dialer(2*time.Second).DialContext(ctx, network, addr)
		}
	}
	ip, err := lookupHost(ctx, host, opt)
	if err != nil || ip == "" {
		if p.bound {
			atomic.StoreInt32(&boundDNSDead, 1)
		}
		return ""
	}
	dnsCache.Lock()
	dnsCache.m[host] = dnsEnt{ip, time.Now().Add(5 * time.Minute)}
	dnsCache.Unlock()
	return ip
}

func (p pingNet) resolve(host string) string {
	return p.lookup(host)
}

// queryA: minimal DNS A lookup over UDP through the (possibly bound) socket.
func (p pingNet) queryA(server, host string) string {
	c, err := p.dialer(time.Second).Dial("udp4", server+":53")
	if err != nil {
		return ""
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(900 * time.Millisecond))
	var id [2]byte
	rand.Read(id[:])
	q := []byte{id[0], id[1], 1, 0, 0, 1, 0, 0, 0, 0, 0, 0}
	for _, l := range splitDots(host) {
		if len(l) == 0 || len(l) > 63 {
			return ""
		}
		q = append(q, byte(len(l)))
		q = append(q, l...)
	}
	q = append(q, 0, 0, 1, 0, 1)
	if _, err := c.Write(q); err != nil {
		return ""
	}
	buf := make([]byte, 1500)
	n, err := c.Read(buf)
	if err != nil {
		return ""
	}
	return parseA(buf[:n], id)
}

func splitDots(h string) []string {
	var out []string
	s := 0
	for i := 0; i <= len(h); i++ {
		if i == len(h) || h[i] == '.' {
			if i > s {
				out = append(out, h[s:i])
			}
			s = i + 1
		}
	}
	return out
}

func skipName(b []byte, o int) int {
	for o < len(b) {
		l := int(b[o])
		if l == 0 {
			return o + 1
		}
		if l&0xC0 == 0xC0 {
			return o + 2
		}
		o += l + 1
	}
	return -1
}

func parseA(b []byte, id [2]byte) string {
	if len(b) < 12 || b[0] != id[0] || b[1] != id[1] || b[3]&0x0F != 0 {
		return ""
	}
	qd, an := int(binary.BigEndian.Uint16(b[4:])), int(binary.BigEndian.Uint16(b[6:]))
	o := 12
	for i := 0; i < qd; i++ {
		if o = skipName(b, o); o < 0 || o+4 > len(b) {
			return ""
		}
		o += 4
	}
	for i := 0; i < an; i++ {
		if o = skipName(b, o); o < 0 || o+10 > len(b) {
			return ""
		}
		typ, rl := binary.BigEndian.Uint16(b[o:]), int(binary.BigEndian.Uint16(b[o+8:]))
		o += 10
		if o+rl > len(b) {
			return ""
		}
		if typ == 1 && rl == 4 {
			return net.IP(b[o : o+4]).String()
		}
		o += rl
	}
	return ""
}

// tcpPing measures the TCP handshake to host:port (-1 = timeout / unreachable).
// Two handshakes run together and the faster one is kept, so a single delayed SYN
// does not decide the latency and a lost first packet still gets a second try.
func (p pingNet) tcpPing(host string, port int) int {
	ip := p.resolve(host)
	if ip == "" {
		return -1
	}
	addr := net.JoinHostPort(ip, strconv.Itoa(port))
	type res struct {
		ms int
		ok bool
	}
	ch := make(chan res, 2)
	for i := 0; i < 2; i++ {
		go func() {
			t0 := time.Now()
			c, err := p.dialer(1200*time.Millisecond).Dial("tcp", addr)
			if err != nil {
				ch <- res{}
				return
			}
			c.Close()
			ms := int(time.Since(t0).Milliseconds())
			if ms < 1 {
				ms = 1
			}
			ch <- res{ms, true}
		}()
	}
	best := -1
	for i := 0; i < 2; i++ {
		r := <-ch
		if r.ok && (best < 0 || r.ms < best) {
			best = r.ms
		}
	}
	return best
}
