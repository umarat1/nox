package engine

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"net"
	"net/http"
	"net/url"
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
	if net.ParseIP(host) != nil {
		return host
	}
	dnsCache.Lock()
	if e, ok := dnsCache.m[host]; ok && time.Now().Before(e.exp) {
		dnsCache.Unlock()
		return e.ip
	}
	dnsCache.Unlock()
	ip := ""
	for _, s := range []string{"77.88.8.8", "1.1.1.1"} {
		if ip = p.queryA(s, host); ip != "" && !isFakeIP(net.ParseIP(ip)) {
			break
		}
		ip = ""
	}
	if ip == "" {
		ip = p.dohA(host) // UDP/53 filtered on some networks
	}
	if ip != "" {
		dnsCache.Lock()
		dnsCache.m[host] = dnsEnt{ip, time.Now().Add(5 * time.Minute)}
		dnsCache.Unlock()
		return ip
	}
	return p.resolve(host)
}

// dohA: A record over DNS-over-HTTPS to IP-addressed resolvers (no DNS needed to reach them).
func (p pingNet) dohA(host string) string {
	tr := &http.Transport{Proxy: nil, DialContext: p.dialer(3 * time.Second).DialContext,
		TLSHandshakeTimeout: 3 * time.Second}
	defer tr.CloseIdleConnections()
	cl := &http.Client{Timeout: 4 * time.Second, Transport: tr}
	for _, u := range []string{"https://1.1.1.1/dns-query", "https://8.8.8.8/resolve"} {
		req, _ := http.NewRequest("GET", u+"?type=A&name="+url.QueryEscape(host), nil)
		req.Header.Set("Accept", "application/dns-json")
		r, err := cl.Do(req)
		if err != nil {
			continue
		}
		var d struct {
			Answer []struct {
				Type int
				Data string
			}
		}
		json.NewDecoder(r.Body).Decode(&d)
		r.Body.Close()
		for _, a := range d.Answer {
			if ip := net.ParseIP(a.Data); a.Type == 1 && ip != nil && !isFakeIP(ip) {
				return a.Data
			}
		}
	}
	return ""
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
func (p pingNet) resolve(host string) string {
	if ip := net.ParseIP(host); ip != nil {
		return host
	}
	dnsCache.Lock()
	if e, ok := dnsCache.m[host]; ok && time.Now().Before(e.exp) {
		dnsCache.Unlock()
		return e.ip
	}
	dnsCache.Unlock()
	ip := ""
	if p.bound && atomic.LoadInt32(&boundDNSDead) == 0 {
		for _, s := range []string{"77.88.8.8", "1.1.1.1"} {
			if ip = p.queryA(s, host); ip != "" {
				break
			}
		}
		if ip == "" {
			atomic.StoreInt32(&boundDNSDead, 1) // e.g. blocked by strict_route firewall: use system DNS for this run
		}
	}
	if ip == "" {
		ctx, cancel := context.WithTimeout(context.Background(), 2500*time.Millisecond)
		ips, _ := net.DefaultResolver.LookupIP(ctx, "ip", host)
		cancel()
		for _, x := range ips {
			if x.To4() != nil && !isFakeIP(x) {
				ip = x.String()
				break
			}
		}
		if ip == "" {
			for _, x := range ips {
				if !isFakeIP(x) {
					ip = x.String()
					break
				}
			}
		}
	}
	if ip != "" {
		dnsCache.Lock()
		dnsCache.m[host] = dnsEnt{ip, time.Now().Add(5 * time.Minute)}
		dnsCache.Unlock()
	}
	return ip
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

// tcpPing measures the TCP handshake time to host:port (-1 = timeout / unreachable).
func (p pingNet) tcpPing(host string, port int) int {
	ip := p.resolve(host)
	if ip == "" {
		return -1
	}
	t0 := time.Now()
	c, err := p.dialer(2500*time.Millisecond).Dial("tcp", net.JoinHostPort(ip, strconv.Itoa(port)))
	if err != nil {
		return -1
	}
	c.Close()
	ms := int(time.Since(t0).Milliseconds())
	if ms < 1 {
		ms = 1
	}
	return ms
}
