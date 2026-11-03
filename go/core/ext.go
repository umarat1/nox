package core

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

// ExtType: protocols served in-process by nox/extra behind a loopback SOCKS5 (sing-box dials it).
const ExtType = "_ext"

func IsExt(raw []byte) bool {
	var w struct{ Type string }
	return json.Unmarshal(raw, &w) == nil && w.Type == ExtType
}

func extServer(name, label, host string, port int, kind string, cfg map[string]any) (Server, error) {
	if host == "" {
		return Server{}, errors.New("неверный адрес")
	}
	if kind == "mihomo" {
		cfg["name"] = "x"
		cfg["server"] = host
		if _, ok := cfg["port"]; !ok && port > 0 {
			cfg["port"] = port
		}
	}
	return mk(name, label, host, port, map[string]any{"type": ExtType, "kind": kind, "cfg": cfg, "server": host, "server_port": port})
}

func parseExt(s string) (Server, bool, error) {
	low := strings.ToLower(s)
	i := strings.Index(low, "://")
	if i <= 0 {
		return Server{}, false, nil
	}
	switch low[:i] {
	case "juicity":
		u, err := url.Parse(s)
		if err != nil {
			return Server{}, true, err
		}
		p, _ := strconv.Atoi(u.Port())
		link := s
		if j := strings.Index(link, "#"); j >= 0 {
			link = link[:j]
		}
		sv, err := extServer(fragName(u), "Juicity", u.Hostname(), p, "juicity", map[string]any{"link": link})
		return sv, true, err
	case "mierus", "mieru":
		u, err := url.Parse(s)
		if err != nil {
			return Server{}, true, err
		}
		q := u.Query()
		pw, _ := u.User.Password()
		cfg := map[string]any{"type": "mieru", "username": u.User.Username(), "password": pw,
			"transport": strings.ToUpper(firstNonEmpty(q.Get("protocol"), "TCP"))}
		ps := firstNonEmpty(q.Get("port"), u.Port())
		port := 0
		if strings.Contains(ps, "-") {
			cfg["port-range"] = ps
			port, _ = strconv.Atoi(strings.SplitN(ps, "-", 2)[0])
		} else {
			port, _ = strconv.Atoi(ps)
			cfg["port"] = port
		}
		if m := q.Get("multiplexing"); m != "" {
			cfg["multiplexing"] = m
		}
		if cfg["transport"] == "UDP" {
			cfg["udp"] = true
		}
		name := fragName(u)
		if name == "" {
			name = q.Get("profile")
		}
		sv, err := extServer(name, "Mieru", u.Hostname(), port, "mihomo", cfg)
		return sv, true, err
	case "snell":
		u, err := url.Parse(s)
		if err != nil {
			return Server{}, true, err
		}
		q := u.Query()
		p, _ := strconv.Atoi(u.Port())
		psk := u.User.Username()
		if pw, ok := u.User.Password(); ok && psk == "" {
			psk = pw
		}
		cfg := map[string]any{"type": "snell", "psk": psk, "udp": true}
		if v, _ := strconv.Atoi(firstNonEmpty(q.Get("version"), "3")); v > 0 {
			cfg["version"] = v
		}
		if o := q.Get("obfs"); o != "" && o != "none" {
			cfg["obfs-opts"] = map[string]any{"mode": o, "host": firstNonEmpty(q.Get("obfs-host"), "bing.com")}
		}
		sv, err := extServer(fragName(u), "Snell", u.Hostname(), p, "mihomo", cfg)
		return sv, true, err
	case "shadowquic", "sq":
		u, err := url.Parse(s)
		if err != nil {
			return Server{}, true, err
		}
		q := u.Query()
		p, _ := strconv.Atoi(u.Port())
		pw, _ := u.User.Password()
		cfg := map[string]any{"type": "shadowquic", "username": u.User.Username(), "password": pw, "udp": true}
		if v := q.Get("sni"); v != "" {
			cfg["sni"] = v
		}
		if v := q.Get("alpn"); v != "" {
			cfg["alpn"] = strings.Split(v, ",")
		}
		if v := firstNonEmpty(q.Get("congestion"), q.Get("congestion_control"), q.Get("congestion-controller")); v != "" {
			cfg["congestion-controller"] = v
		}
		if v := firstNonEmpty(q.Get("quic-versions"), q.Get("quic_version")); v != "" {
			cfg["quic-versions"] = strings.Split(v, ",")
		}
		if truthy(firstNonEmpty(q.Get("zero-rtt"), q.Get("zero_rtt"))) {
			cfg["zero-rtt"] = true
		}
		sv, err := extServer(fragName(u), "ShadowQUIC", u.Hostname(), p, "mihomo", cfg)
		return sv, true, err
	case "tt":
		sv, err := parseTT(s)
		return sv, true, err
	case "trusttunnel":
		u, err := url.Parse(s)
		if err != nil {
			return Server{}, true, err
		}
		q := u.Query()
		p, _ := strconv.Atoi(u.Port())
		pw, _ := u.User.Password()
		cfg := map[string]any{"type": "trusttunnel", "username": u.User.Username(), "password": pw, "port": p,
			"sni": firstNonEmpty(q.Get("sni"), u.Hostname()), "udp": true}
		if truthy(q.Get("insecure")) {
			cfg["skip-cert-verify"] = true
		}
		if truthy(q.Get("quic")) {
			cfg["quic"] = true
		}
		sv, err := extServer(fragName(u), "TrustTunnel", u.Hostname(), p, "mihomo", cfg)
		return sv, true, err
	case "naive+https", "naive+quic", "naive":
		u, err := url.Parse(s)
		if err != nil {
			return Server{}, true, err
		}
		q := u.Query()
		scheme := "https"
		if strings.HasSuffix(low[:i], "quic") {
			scheme = "quic"
		}
		p, _ := strconv.Atoi(u.Port())
		if p == 0 {
			p = 443
		}
		pw, _ := u.User.Password()
		h := u.Hostname()
		cfg := map[string]any{"scheme": scheme, "host": h, "port": p, "user": u.User.Username(), "pass": pw}
		if sni := firstNonEmpty(q.Get("sni"), q.Get("peer")); sni != "" && sni != h {
			cfg["host"], cfg["ip"] = sni, h
		}
		sv, err := extServer(fragName(u), "Naive", h, p, "naive", cfg)
		return sv, true, err
	}
	return Server{}, false, nil
}

func fragName(u *url.URL) string { return u.Fragment }

func firstNonEmpty(v ...string) string {
	for _, x := range v {
		if x != "" {
			return x
		}
	}
	return ""
}

func ttVarint(b []byte) (uint64, int) {
	if len(b) == 0 {
		return 0, 0
	}
	n := 1 << (b[0] >> 6)
	if len(b) < n {
		return 0, 0
	}
	v := uint64(b[0] & 0x3f)
	for i := 1; i < n; i++ {
		v = v<<8 | uint64(b[i])
	}
	return v, n
}

// parseTT: TrustTunnel deep link tt://?<base64url TLV> (DEEP_LINK.md v2).
func parseTT(s string) (Server, error) {
	body := s[strings.Index(s, "://")+3:]
	body = strings.TrimPrefix(body, "?")
	name := ""
	if j := strings.Index(body, "#"); j >= 0 {
		name, _ = url.QueryUnescape(body[j+1:])
		body = body[:j]
	}
	b, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(body, "="))
	if err != nil {
		if b, err = base64.StdEncoding.DecodeString(body); err != nil {
			return Server{}, errors.New("tt: неверная ссылка")
		}
	}
	var host, sni, user, pass, addr string
	skip, h3 := false, false
	for len(b) > 0 {
		tag, n := ttVarint(b)
		if n == 0 {
			break
		}
		b = b[n:]
		l, m := ttVarint(b)
		if m == 0 || int(l) > len(b)-m {
			break
		}
		v := b[m : m+int(l)]
		b = b[m+int(l):]
		switch tag {
		case 1:
			host = string(v)
		case 2:
			if addr == "" {
				addr = string(v)
			}
		case 3:
			sni = string(v)
		case 5:
			user = string(v)
		case 6:
			pass = string(v)
		case 7:
			skip = len(v) > 0 && v[0] == 1
		case 9:
			x, _ := ttVarint(v)
			h3 = x == 2
		case 0x0c:
			if name == "" {
				name = string(v)
			}
		}
	}
	h, ps, err := splitHP(addr)
	if err != nil {
		return Server{}, fmt.Errorf("tt: неверный адрес %q", addr)
	}
	cfg := map[string]any{"type": "trusttunnel", "username": user, "password": pass, "port": ps,
		"sni": firstNonEmpty(sni, host), "udp": true}
	if skip {
		cfg["skip-cert-verify"] = true
	}
	if h3 {
		cfg["quic"] = true
	}
	return extServer(name, "TrustTunnel", h, ps, "mihomo", cfg)
}
