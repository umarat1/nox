// Package core: share-link / subscription parsing and sing-box config building for VPS (Windows).
package core

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"
)

type Server struct {
	ID       string          `json:"id"`
	SubID    string          `json:"subId"`
	Name     string          `json:"name"`
	Type     string          `json:"type"`
	Host     string          `json:"host"`
	Port     int             `json:"port"`
	Outbound json.RawMessage `json:"outbound"`
	Ping     int             `json:"ping"`              // -1 timeout, 0 unknown
	Desc     string          `json:"desc,omitempty"`    // Remnawave serverDescription
	Members  []string        `json:"members,omitempty"` // balancer member names
}

const BalancerType = "_balancer"
const BalancerLabel = "Автовыбор"

// SplitDesc strips a Remnawave "?serverDescription=<base64>" suffix (after #remark) from a share link.
func SplitDesc(line string) (string, string) {
	q := strings.LastIndex(line, "?serverDescription=")
	if q < 0 || !strings.Contains(line[:q], "#") {
		return line, ""
	}
	d, ok := B64(line[q+19:])
	if !ok {
		d = ""
	}
	return line[:q], strings.TrimSpace(d)
}

// DescMap: remark -> description from a (base64 or plain) link list.
func DescMap(body string) map[string]string {
	t := strings.TrimSpace(body)
	if !strings.Contains(t, "://") {
		if d, ok := B64(t); ok {
			t = d
		}
	}
	m := map[string]string{}
	for _, line := range strings.Split(t, "\n") {
		l, d := SplitDesc(strings.TrimSpace(line))
		if d == "" {
			continue
		}
		if h := strings.Index(l, "#"); h >= 0 {
			r := l[h+1:]
			if u, err := url.QueryUnescape(r); err == nil {
				r = u
			}
			m[strings.TrimSpace(r)] = d
		}
	}
	return m
}

type ParseResult struct {
	Servers []Server
	Errors  []string
}

var schemes = map[string]bool{"vless": true, "vmess": true, "trojan": true, "ss": true, "hysteria2": true, "hy2": true,
	"hysteria": true, "tuic": true, "anytls": true, "socks": true, "socks5": true, "wireguard": true, "wg": true, "qwdtt": true, "sstp": true}

func IsShareLink(s string) bool {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(strings.ToLower(s), "qwdtt:") {
		return true
	}
	i := strings.Index(s, "://")
	return i > 0 && schemes[strings.ToLower(s[:i])]
}

func B64(s string) (string, bool) {
	s = strings.TrimSpace(s)
	s = strings.NewReplacer("\n", "", "\r", "", " ", "").Replace(s)
	for _, enc := range []*base64.Encoding{base64.StdEncoding, base64.RawStdEncoding, base64.URLEncoding, base64.RawURLEncoding} {
		if b, err := enc.DecodeString(s); err == nil {
			return string(b), true
		}
	}
	return "", false
}

// ParseContent parses a subscription body: base64, plain link list, or sing-box JSON.
func ParseContent(content string) ParseResult {
	text := strings.TrimPrefix(strings.TrimSpace(content), "\uFEFF")
	if strings.HasPrefix(text, "{") || strings.HasPrefix(text, "[") {
		if r, err := parseSingBoxJSON(text); err == nil {
			return r
		}
	}
	hasLink := false
	for _, l := range strings.Split(text, "\n") {
		if IsShareLink(l) {
			hasLink = true
			break
		}
	}
	if !hasLink {
		if d, ok := B64(text); ok {
			text = d
		}
	}
	var r ParseResult
	for _, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") || !IsShareLink(line) {
			continue
		}
		line, desc := SplitDesc(line)
		s, err := ParseLink(line)
		s.Desc = desc
		if err != nil {
			sch := line
			if i := strings.Index(line, ":"); i > 0 {
				sch = line[:i]
			}
			r.Errors = append(r.Errors, sch+": "+err.Error())
			continue
		}
		r.Servers = append(r.Servers, s)
	}
	return r
}

var proxyTypes = map[string]bool{"vless": true, "vmess": true, "trojan": true, "shadowsocks": true, "hysteria": true,
	"hysteria2": true, "tuic": true, "anytls": true, "socks": true, "http": true, "ssh": true, "wireguard": true}

func parseSingBoxJSON(text string) (ParseResult, error) {
	var items []map[string]any
	var root any
	if err := json.Unmarshal([]byte(text), &root); err != nil {
		return ParseResult{}, err
	}
	switch v := root.(type) {
	case []any:
		for _, x := range v {
			if m, ok := x.(map[string]any); ok {
				items = append(items, m)
			}
		}
	case map[string]any:
		if _, ok := v["type"]; ok {
			items = append(items, v)
		} else {
			for _, k := range []string{"outbounds", "endpoints"} {
				if arr, ok := v[k].([]any); ok {
					for _, x := range arr {
						if m, ok := x.(map[string]any); ok {
							items = append(items, m)
						}
					}
				}
			}
		}
	}
	var r ParseResult
	var urltests []map[string]any
	for _, it := range items {
		t, _ := it["type"].(string)
		if t == "urltest" {
			urltests = append(urltests, it)
			continue
		}
		if !proxyTypes[t] {
			continue
		}
		if _, ok := it["detour"]; ok {
			r.Errors = append(r.Errors, t+": detour не поддерживается")
			continue
		}
		tag, _ := it["tag"].(string)
		host, _ := it["server"].(string)
		port := 0
		if p, ok := it["server_port"].(float64); ok {
			port = int(p)
		}
		if peers, ok := it["peers"].([]any); ok && len(peers) > 0 {
			if p0, ok := peers[0].(map[string]any); ok {
				host, _ = p0["address"].(string)
				if p, ok := p0["port"].(float64); ok {
					port = int(p)
				}
			}
		}
		delete(it, "tag")
		b, _ := json.Marshal(it)
		if tag == "" {
			tag = fmt.Sprintf("%s %s:%d", t, host, port)
		}
		r.Servers = append(r.Servers, Server{Name: tag, Type: DisplayType(t), Host: host, Port: port, Outbound: b})
	}
	// sing-box urltest groups (Remnawave "Auto") -> local balancer, listed first
	byName := map[string]Server{}
	for _, sv := range r.Servers {
		byName[sv.Name] = sv
	}
	var bals []Server
	for _, u := range urltests {
		tag, _ := u["tag"].(string)
		arr, _ := u["outbounds"].([]any)
		var names []string
		var obs []json.RawMessage
		for _, x := range arr {
			if n, ok := x.(string); ok {
				if sv, ok := byName[n]; ok && sv.Type != "WireGuard" {
					names = append(names, n)
					obs = append(obs, sv.Outbound)
				}
			}
		}
		if len(names) < 2 {
			continue
		}
		ob := map[string]any{"type": BalancerType, "outbounds": obs, "url": "https://www.gstatic.com/generate_204", "interval": "3m", "tolerance": 50}
		if v, ok := u["url"].(string); ok && v != "" {
			ob["url"] = v
		}
		if v, ok := u["interval"].(string); ok && v != "" {
			ob["interval"] = v
		}
		if v, ok := u["tolerance"].(float64); ok {
			ob["tolerance"] = int(v)
		}
		b, _ := json.Marshal(ob)
		if tag == "" {
			tag = BalancerLabel
		}
		bals = append(bals, Server{Name: tag, Type: BalancerLabel, Outbound: b, Members: names})
	}
	r.Servers = append(bals, r.Servers...)
	if len(items) > 0 && len(r.Servers) == 0 && len(r.Errors) == 0 {
		return r, errors.New("no proxies")
	}
	return r, nil
}

func DisplayType(t string) string {
	m := map[string]string{"vless": "VLESS", "vmess": "VMess", "trojan": "Trojan", "shadowsocks": "Shadowsocks", "hysteria": "Hysteria",
		"hysteria2": "Hysteria2", "tuic": "TUIC", "anytls": "AnyTLS", "wireguard": "WireGuard", "socks": "SOCKS5", "http": "HTTP", "ssh": "SSH", "_qwdtt": "qWDTT", "_sstp": "SSTP", "_xray": "XHTTP"}
	if v, ok := m[t]; ok {
		return v
	}
	return t
}

type link struct {
	scheme, user, pass, host string
	port                     int
	q                        url.Values
	name                     string
	hasPass                  bool
}

func splitLink(s string) (*link, error) {
	l := &link{}
	i := strings.Index(s, "://")
	l.scheme = strings.ToLower(s[:i])
	rest := s[i+3:]
	if j := strings.Index(rest, "#"); j >= 0 {
		l.name, _ = url.PathUnescape(rest[j+1:])
		if n, err := url.QueryUnescape(rest[j+1:]); err == nil {
			l.name = n
		}
		rest = rest[:j]
	}
	if j := strings.Index(rest, "?"); j >= 0 {
		l.q, _ = url.ParseQuery(rest[j+1:])
		rest = rest[:j]
	} else {
		l.q = url.Values{}
	}
	rest = strings.TrimSuffix(rest, "/")
	if j := strings.LastIndex(rest, "@"); j >= 0 {
		ui := rest[:j]
		rest = rest[j+1:]
		if k := strings.Index(ui, ":"); k >= 0 {
			l.user, _ = url.PathUnescape(ui[:k])
			l.pass, _ = url.PathUnescape(ui[k+1:])
			l.hasPass = true
		} else {
			l.user, _ = url.PathUnescape(ui)
		}
	}
	if j := strings.Index(rest, "/"); j >= 0 {
		rest = rest[:j]
	}
	h, p, err := net.SplitHostPort(rest)
	if err != nil {
		return nil, fmt.Errorf("неверный адрес %q", rest)
	}
	// port hopping "443,1000-2000" -> take first
	ps := strings.FieldsFunc(p, func(r rune) bool { return r == ',' || r == '-' })
	if len(ps) == 0 {
		return nil, errors.New("нет порта")
	}
	l.port, err = strconv.Atoi(ps[0])
	if err != nil || l.port <= 0 || l.port > 65535 {
		return nil, errors.New("неверный порт")
	}
	l.host = h
	return l, nil
}

func (l *link) g(keys ...string) string {
	for _, k := range keys {
		if v := strings.TrimSpace(l.q.Get(k)); v != "" {
			return v
		}
	}
	return ""
}

func truthy(s string) bool {
	return s == "1" || strings.EqualFold(s, "true") || strings.EqualFold(s, "yes")
}

func csv(s string) []string {
	var out []string
	for _, x := range strings.Split(s, ",") {
		if x = strings.TrimSpace(x); x != "" {
			out = append(out, x)
		}
	}
	return out
}

func tlsFrom(l *link, security string, forceTLS bool) map[string]any {
	if security == "" && !forceTLS || security == "none" {
		return nil
	}
	t := map[string]any{"enabled": true}
	if sni := l.g("sni", "peer", "servername"); sni != "" {
		t["server_name"] = sni
	} else if net.ParseIP(l.host) == nil {
		t["server_name"] = l.host
	}
	if truthy(l.g("allowInsecure", "insecure", "allow_insecure")) {
		t["insecure"] = true
	}
	if a := l.g("alpn"); a != "" {
		t["alpn"] = csv(a)
	}
	fp := l.g("fp")
	if security == "reality" {
		t["reality"] = map[string]any{"enabled": true, "public_key": l.g("pbk"), "short_id": l.g("sid")}
		if fp == "" {
			fp = "chrome"
		}
	}
	if fp != "" && fp != "none" {
		if fp == "random" || fp == "randomized" {
			fp = "randomized"
		}
		t["utls"] = map[string]any{"enabled": true, "fingerprint": fp}
	}
	return t
}

func transportFrom(typ, host, path, service string, l *link) (map[string]any, error) {
	switch typ {
	case "", "tcp", "raw":
		if l != nil && l.g("headerType") == "http" {
			t := map[string]any{"type": "http"}
			if host != "" {
				t["host"] = csv(host)
			}
			if path != "" {
				t["path"] = path
			}
			return t, nil
		}
		return nil, nil
	case "ws":
		t := map[string]any{"type": "ws"}
		if path != "" {
			p := path
			if u, err := url.Parse(path); err == nil && u.Query().Get("ed") != "" {
				ed, _ := strconv.Atoi(u.Query().Get("ed"))
				q := u.Query()
				q.Del("ed")
				u.RawQuery = q.Encode()
				p = u.String()
				t["max_early_data"] = ed
				t["early_data_header_name"] = "Sec-WebSocket-Protocol"
			}
			t["path"] = p
		}
		if host != "" {
			t["headers"] = map[string]any{"Host": host}
		}
		return t, nil
	case "grpc":
		return map[string]any{"type": "grpc", "service_name": service}, nil
	case "httpupgrade":
		t := map[string]any{"type": "httpupgrade", "path": path}
		if host != "" {
			t["host"] = host
		}
		return t, nil
	case "http", "h2":
		t := map[string]any{"type": "http"}
		if host != "" {
			t["host"] = csv(host)
		}
		if path != "" {
			t["path"] = path
		}
		return t, nil
	case "quic":
		return map[string]any{"type": "quic"}, nil
	}
	return nil, fmt.Errorf("транспорт %s не поддерживается sing-box", typ)
}

func mk(name, typ string, host string, port int, ob map[string]any) (Server, error) {
	b, err := json.Marshal(ob)
	if name == "" {
		name = fmt.Sprintf("%s:%d", host, port)
	}
	return Server{Name: name, Type: typ, Host: host, Port: port, Outbound: b}, err
}

func ParseLink(s string) (Server, error) {
	s = strings.TrimSpace(s)
	low := strings.ToLower(s)
	if strings.HasPrefix(low, "qwdtt:") {
		q, err := ParseQwdtt(s)
		if err != nil {
			return Server{}, err
		}
		h, p, _ := splitHP(q.Peer)
		return mk(q.Name, "qWDTT", h, p, q.Outbound())
	}
	if strings.HasPrefix(low, "sstp://") {
		return ParseSSTP(s)
	}
	if strings.HasPrefix(low, "vmess://") {
		return parseVmess(s)
	}
	if strings.HasPrefix(low, "ss://") {
		return parseSS(s)
	}
	l, err := splitLink(s)
	if err != nil {
		return Server{}, err
	}
	if (l.scheme == "vless" || l.scheme == "trojan") && strings.EqualFold(l.g("type"), "xhttp") {
		return xrayFromLink(l) // sing-box has no XHTTP: Xray-core runs it
	}
	switch l.scheme {
	case "vless":
		ob := map[string]any{"type": "vless", "server": l.host, "server_port": l.port, "uuid": l.user}
		if f := l.g("flow"); f != "" {
			ob["flow"] = f
		}
		if t := tlsFrom(l, l.g("security"), false); t != nil {
			ob["tls"] = t
		}
		tr, err := transportFrom(l.g("type"), l.g("host"), l.g("path"), l.g("serviceName", "service_name"), l)
		if err != nil {
			return Server{}, err
		}
		if tr != nil {
			ob["transport"] = tr
		}
		label := "VLESS"
		if l.g("security") == "reality" {
			label = "VLESS Reality"
		}
		return mk(l.name, label, l.host, l.port, ob)
	case "trojan":
		ob := map[string]any{"type": "trojan", "server": l.host, "server_port": l.port, "password": l.user}
		sec := l.g("security")
		if sec == "" {
			sec = "tls"
		}
		if t := tlsFrom(l, sec, false); t != nil {
			ob["tls"] = t
		}
		tr, err := transportFrom(l.g("type"), l.g("host"), l.g("path"), l.g("serviceName"), l)
		if err != nil {
			return Server{}, err
		}
		if tr != nil {
			ob["transport"] = tr
		}
		return mk(l.name, "Trojan", l.host, l.port, ob)
	case "hysteria2", "hy2":
		pw := l.user
		if l.hasPass {
			pw = l.user + ":" + l.pass
		}
		if pw == "" {
			pw = l.g("auth", "password")
		}
		ob := map[string]any{"type": "hysteria2", "server": l.host, "server_port": l.port, "password": pw, "tls": tlsFrom(l, "tls", true)}
		if o := l.g("obfs"); o != "" && o != "none" {
			ob["obfs"] = map[string]any{"type": o, "password": l.g("obfs-password", "obfs_password")}
		}
		if mp := l.g("mport"); mp != "" {
			ob["server_ports"] = []string{strings.ReplaceAll(mp, "-", ":")}
		}
		return mk(l.name, "Hysteria2", l.host, l.port, ob)
	case "hysteria":
		ob := map[string]any{"type": "hysteria", "server": l.host, "server_port": l.port, "tls": tlsFrom(l, "tls", true)}
		if a := l.g("auth", "auth_str"); a != "" {
			ob["auth_str"] = a
		}
		up, _ := strconv.Atoi(l.g("upmbps", "up"))
		down, _ := strconv.Atoi(l.g("downmbps", "down"))
		if up == 0 {
			up = 50
		}
		if down == 0 {
			down = 100
		}
		ob["up_mbps"], ob["down_mbps"] = up, down
		if o := l.g("obfsParam", "obfs"); o != "" && o != "xplus" {
			ob["obfs"] = o
		} else if o := l.g("obfsParam"); o != "" {
			ob["obfs"] = o
		}
		return mk(l.name, "Hysteria", l.host, l.port, ob)
	case "tuic":
		ob := map[string]any{"type": "tuic", "server": l.host, "server_port": l.port, "uuid": l.user, "password": l.pass, "tls": tlsFrom(l, "tls", true)}
		if c := l.g("congestion_control", "congestion"); c != "" {
			ob["congestion_control"] = c
		}
		if m := l.g("udp_relay_mode"); m != "" {
			ob["udp_relay_mode"] = m
		}
		return mk(l.name, "TUIC", l.host, l.port, ob)
	case "anytls":
		ob := map[string]any{"type": "anytls", "server": l.host, "server_port": l.port, "password": l.user, "tls": tlsFrom(l, "tls", true)}
		return mk(l.name, "AnyTLS", l.host, l.port, ob)
	case "socks", "socks5":
		ob := map[string]any{"type": "socks", "server": l.host, "server_port": l.port}
		u, p := l.user, l.pass
		if !l.hasPass && u != "" {
			if d, ok := B64(u); ok && strings.Contains(d, ":") {
				u, p, _ = strings.Cut(d, ":")
			}
		}
		if u != "" {
			ob["username"], ob["password"] = u, p
		}
		return mk(l.name, "SOCKS5", l.host, l.port, ob)
	case "wireguard", "wg":
		pk := l.user
		if pk == "" {
			pk = l.g("privatekey", "private_key")
		}
		addr := csv(l.g("address", "ip"))
		for i, a := range addr {
			if !strings.Contains(a, "/") {
				if strings.Contains(a, ":") {
					addr[i] = a + "/128"
				} else {
					addr[i] = a + "/32"
				}
			}
		}
		if len(addr) == 0 {
			addr = []string{"10.0.0.2/32"}
		}
		peer := map[string]any{"address": l.host, "port": l.port, "public_key": l.g("publickey", "public_key", "peer_public_key"), "allowed_ips": []string{"0.0.0.0/0", "::/0"}}
		if psk := l.g("presharedkey", "pre_shared_key"); psk != "" {
			peer["pre_shared_key"] = psk
		}
		mtu, _ := strconv.Atoi(l.g("mtu"))
		if mtu == 0 {
			mtu = 1280
		}
		ob := map[string]any{"type": "wireguard", "address": addr, "private_key": pk, "mtu": mtu, "peers": []any{peer}}
		return mk(l.name, "WireGuard", l.host, l.port, ob)
	}
	return Server{}, fmt.Errorf("неизвестная схема %s", l.scheme)
}

func parseVmess(s string) (Server, error) {
	body := s[len("vmess://"):]
	if i := strings.Index(body, "#"); i >= 0 {
		body = body[:i]
	}
	d, ok := B64(body)
	if !ok || !strings.HasPrefix(strings.TrimSpace(d), "{") {
		return Server{}, errors.New("неверный vmess")
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(d), &m); err != nil {
		return Server{}, err
	}
	str := func(k string) string {
		switch v := m[k].(type) {
		case string:
			return v
		case float64:
			return strconv.Itoa(int(v))
		}
		return ""
	}
	port, _ := strconv.Atoi(str("port"))
	host := str("add")
	if host == "" || port == 0 {
		return Server{}, errors.New("vmess: нет адреса")
	}
	aid, _ := strconv.Atoi(str("aid"))
	sec := str("scy")
	if sec == "" {
		sec = "auto"
	}
	ob := map[string]any{"type": "vmess", "server": host, "server_port": port, "uuid": str("id"), "alter_id": aid, "security": sec}
	q := url.Values{}
	for _, k := range []string{"sni", "alpn", "fp"} {
		if v := str(k); v != "" {
			q.Set(k, v)
		}
	}
	if truthy(str("allowInsecure")) {
		q.Set("allowInsecure", "1")
	}
	if str("type") == "http" {
		q.Set("headerType", "http")
	}
	l := &link{host: host, port: port, q: q}
	if t := tlsFrom(l, str("tls"), false); t != nil {
		if str("sni") == "" && str("host") != "" {
			t["server_name"] = str("host")
		}
		ob["tls"] = t
	}
	tr, err := transportFrom(str("net"), str("host"), str("path"), str("path"), l)
	if err != nil {
		return Server{}, err
	}
	if tr != nil {
		ob["transport"] = tr
	}
	return mk(str("ps"), "VMess", host, port, ob)
}

func parseSS(s string) (Server, error) {
	body := s[len("ss://"):]
	name := ""
	if i := strings.Index(body, "#"); i >= 0 {
		name, _ = url.QueryUnescape(body[i+1:])
		body = body[:i]
	}
	query := ""
	if i := strings.Index(body, "?"); i >= 0 {
		query = body[i+1:]
		body = body[:i]
	}
	body = strings.TrimSuffix(body, "/")
	var method, pass, hp string
	if i := strings.LastIndex(body, "@"); i >= 0 {
		ui := body[:i]
		hp = body[i+1:]
		ui, _ = url.PathUnescape(ui)
		if d, ok := B64(ui); ok && strings.Contains(d, ":") {
			ui = d
		}
		method, pass, _ = strings.Cut(ui, ":")
	} else {
		d, ok := B64(body)
		if !ok {
			return Server{}, errors.New("неверный ss")
		}
		j := strings.LastIndex(d, "@")
		if j < 0 {
			return Server{}, errors.New("неверный ss")
		}
		method, pass, _ = strings.Cut(d[:j], ":")
		hp = d[j+1:]
	}
	h, p, err := splitHP(hp)
	if err != nil {
		return Server{}, err
	}
	if method == "" {
		return Server{}, errors.New("ss: нет метода")
	}
	ob := map[string]any{"type": "shadowsocks", "server": h, "server_port": p, "method": method, "password": pass}
	if query != "" {
		q, _ := url.ParseQuery(query)
		if pl := q.Get("plugin"); pl != "" {
			name0, opts, _ := strings.Cut(pl, ";")
			if name0 == "simple-obfs" {
				name0 = "obfs-local"
			}
			ob["plugin"], ob["plugin_opts"] = name0, opts
		}
	}
	return mk(name, "Shadowsocks", h, p, ob)
}

func splitHP(hp string) (string, int, error) {
	h, ps, err := net.SplitHostPort(strings.TrimSpace(hp))
	if err != nil {
		return "", 0, fmt.Errorf("неверный адрес")
	}
	p, err := strconv.Atoi(ps)
	if err != nil || p <= 0 || p > 65535 {
		return "", 0, fmt.Errorf("неверный порт")
	}
	return h, p, nil
}
