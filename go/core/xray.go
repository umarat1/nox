package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strings"
)

// XrayType marks servers that sing-box cannot run (VLESS/Trojan over XHTTP). The outbound
// JSON is {"type":"_xray","server":host,"server_port":port,"xray":<Xray-core outbound>}; at
// runtime Xray-core serves it as a local SOCKS5 inbound and sing-box (TUN, routing, ping)
// chains to that.
const XrayType = "_xray"

// IsXray reports whether a server outbound has to be run by Xray-core.
func IsXray(raw []byte) bool {
	var h struct{ Type string }
	return json.Unmarshal(raw, &h) == nil && h.Type == XrayType
}

// xrayFromLink builds the Xray outbound for vless:// or trojan:// with type=xhttp.
func xrayFromLink(l *link) (Server, error) {
	if l.host == "" || l.port == 0 {
		return Server{}, errors.New("xhttp: нет адреса сервера")
	}
	sec := l.g("security")
	if sec == "" && l.scheme == "trojan" {
		sec = "tls"
	}
	if sec == "" {
		sec = "none"
	}
	xh := map[string]any{"path": "/", "mode": "auto"}
	if p := l.g("path"); p != "" {
		xh["path"] = p
	}
	if h := l.g("host"); h != "" {
		xh["host"] = h
	}
	if m := l.g("mode"); m != "" {
		xh["mode"] = m
	}
	if e := l.g("extra"); e != "" {
		var ex map[string]any
		if json.Unmarshal([]byte(e), &ex) != nil {
			return Server{}, errors.New("xhttp: неверный параметр extra")
		}
		xh["extra"] = ex
	}
	st := map[string]any{"network": "xhttp", "security": sec, "xhttpSettings": xh}
	raw := !strings.EqualFold(l.g("type"), "xhttp")
	if raw { // VLESS Reality over raw TCP (sing-box's REALITY client fails against Xray 26 servers)
		st = map[string]any{"network": "raw", "security": sec}
	}
	sni := l.g("sni", "peer", "servername")
	if sni == "" && net.ParseIP(l.host) == nil {
		sni = l.host
	}
	fp := l.g("fp")
	switch sec {
	case "tls":
		t := map[string]any{"serverName": sni}
		if fp != "" && fp != "none" {
			t["fingerprint"] = fp
		}
		if a := l.g("alpn"); a != "" {
			t["alpn"] = csv(a)
		}
		if truthy(l.g("allowInsecure", "insecure", "allow_insecure")) {
			t["allowInsecure"] = true
		}
		st["tlsSettings"] = t
	case "reality":
		if fp == "" {
			fp = "chrome"
		}
		r := map[string]any{"serverName": sni, "fingerprint": fp, "publicKey": l.g("pbk"), "shortId": l.g("sid")}
		if sx := l.g("spx"); sx != "" {
			r["spiderX"] = sx
		}
		st["realitySettings"] = r
	case "none":
	default:
		return Server{}, fmt.Errorf("xhttp: security=%s не поддерживается", sec)
	}
	var ob map[string]any
	label := "VLESS XHTTP"
	switch l.scheme {
	case "vless":
		enc := l.g("encryption")
		if enc == "" {
			enc = "none"
		}
		u := map[string]any{"id": l.user, "encryption": enc}
		if f := l.g("flow"); f != "" {
			u["flow"] = f
		}
		ob = map[string]any{"protocol": "vless", "settings": map[string]any{"vnext": []any{
			map[string]any{"address": l.host, "port": l.port, "users": []any{u}}}}}
		if sec == "reality" {
			label = "VLESS Reality XHTTP"
			if raw {
				label = "VLESS Reality"
			}
		}
	case "trojan":
		ob = map[string]any{"protocol": "trojan", "settings": map[string]any{"servers": []any{
			map[string]any{"address": l.host, "port": l.port, "password": l.user}}}}
		label = "Trojan XHTTP"
	default:
		return Server{}, fmt.Errorf("xhttp: протокол %s не поддерживается", l.scheme)
	}
	ob["streamSettings"] = st
	return mk(l.name, label, l.host, l.port, map[string]any{"type": XrayType, "server": l.host, "server_port": l.port, "xray": ob})
}

// XrayEntry is one server served by the Xray instance on a loopback SOCKS port.
type XrayEntry struct {
	Outbound json.RawMessage // the server's full "_xray" outbound
	Port     int
	IP       string // optional pre-resolved address (system DNS may be unusable)
}

// XrayConfig builds an Xray-core config: one SOCKS5 inbound (127.0.0.1:Port, UDP on) per
// entry, routed to that entry's outbound.
func XrayConfig(entries []XrayEntry) ([]byte, error) {
	var ins, outs, rules []any
	for i, e := range entries {
		var w struct {
			Server string
			Xray   map[string]any
		}
		if err := json.Unmarshal(e.Outbound, &w); err != nil || w.Xray == nil {
			return nil, errors.New("xray: неверный сервер")
		}
		ob := w.Xray
		if e.IP != "" {
			pinXray(ob, w.Server, e.IP)
		} else if st, ok := ob["streamSettings"].(map[string]any); ok {
			// no usable system resolver (Android binaries): resolve via Xray's own DNS
			so, _ := st["sockopt"].(map[string]any)
			if so == nil {
				so = map[string]any{}
			}
			so["domainStrategy"] = "UseIPv4"
			st["sockopt"] = so
		}
		in, out := fmt.Sprintf("in%d", i), fmt.Sprintf("out%d", i)
		ob["tag"] = out
		ins = append(ins, map[string]any{"tag": in, "listen": "127.0.0.1", "port": e.Port, "protocol": "socks",
			"settings": map[string]any{"auth": "noauth", "udp": true, "ip": "127.0.0.1"}})
		outs = append(outs, ob)
		rules = append(rules, map[string]any{"type": "field", "inboundTag": []string{in}, "outboundTag": out})
	}
	outs = append(outs, map[string]any{"tag": "block", "protocol": "blackhole"})
	cfg := map[string]any{"log": map[string]any{"loglevel": "warning", "access": "none"}, "inbounds": ins, "outbounds": outs,
		"routing": map[string]any{"domainStrategy": "AsIs", "rules": rules},
		"dns":     map[string]any{"servers": []any{"77.88.8.8", "1.1.1.1"}, "queryStrategy": "UseIPv4"}}
	return json.Marshal(cfg)
}

// pinXray dials ip instead of the domain while TLS SNI / XHTTP Host keep the domain.
func pinXray(ob map[string]any, host, ip string) {
	set := func(list []any) {
		for _, x := range list {
			if m, ok := x.(map[string]any); ok {
				m["address"] = ip
			}
		}
	}
	if s, ok := ob["settings"].(map[string]any); ok {
		if v, ok := s["vnext"].([]any); ok {
			set(v)
		}
		if v, ok := s["servers"].([]any); ok {
			set(v)
		}
	}
	if host == "" || net.ParseIP(host) != nil {
		return
	}
	st, _ := ob["streamSettings"].(map[string]any)
	if st == nil {
		return
	}
	for _, k := range []string{"tlsSettings", "realitySettings"} {
		if t, ok := st[k].(map[string]any); ok {
			if sn, _ := t["serverName"].(string); sn == "" {
				t["serverName"] = host
			}
		}
	}
	if xh, ok := st["xhttpSettings"].(map[string]any); ok {
		if h, _ := xh["host"].(string); strings.TrimSpace(h) == "" {
			xh["host"] = host
		}
	}
}
