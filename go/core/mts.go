package core

import (
	"fmt"
	"strings"
)

// «МТС прокси»: every outbound that dials the network itself goes through the operator's
// in-network HTTP proxy (HTTP CONNECT). Works for TCP transports only.
const (
	MtsProxyHost = "192.168.192.192"
	MtsProxyPort = 80
	MtsTag       = "mts-up"
)

func MtsProxyURL() string { return fmt.Sprintf("http://%s:%d", MtsProxyHost, MtsProxyPort) }

// MtsOutbound is the sing-box upstream used as detour.
func MtsOutbound() map[string]any {
	return map[string]any{"type": "http", "tag": MtsTag, "server": MtsProxyHost, "server_port": MtsProxyPort}
}

// MtsXrayOutbound is the Xray upstream used via proxySettings.
func MtsXrayOutbound() map[string]any {
	return map[string]any{"tag": MtsTag, "protocol": "http",
		"settings": map[string]any{"servers": []any{map[string]any{"address": MtsProxyHost, "port": MtsProxyPort}}}}
}

// MtsBlocked returns a reason when an outbound cannot run through an HTTP CONNECT proxy
// (UDP/QUIC transports), "" when it can.
func MtsBlocked(ob map[string]any) string {
	t, _ := ob["type"].(string)
	switch t {
	case "hysteria", "hysteria2", "tuic", "wireguard", "quic", "juicity", "shadowquic":
		return t + " работает только по UDP/QUIC — через HTTP-прокси МТС не идёт"
	}
	if tr, ok := ob["transport"].(map[string]any); ok {
		if tt, _ := tr["type"].(string); tt == "quic" {
			return "транспорт QUIC (UDP) — через HTTP-прокси МТС не идёт"
		}
	}
	if s, _ := ob["network"].(string); s == "udp" {
		return "сервер только UDP — через HTTP-прокси МТС не идёт"
	}
	return ""
}

func mtsSkip(ob map[string]any) bool {
	t, _ := ob["type"].(string)
	switch t {
	case "direct", "block", "dns", "urltest", "selector", "":
		return true
	}
	if _, ok := ob["detour"]; ok {
		return true // a later hop of a chain: dials through the previous hop
	}
	srv, _ := ob["server"].(string)
	// local helpers (Xray / naive / qWDTT loopback): they handle the upstream themselves
	return srv == "127.0.0.1" || srv == "localhost" || strings.HasPrefix(srv, "127.")
}

// ApplyMts sets detour=mts-up on every first-hop outbound. Returns an error for transports
// that cannot be chained.
func ApplyMts(outs []map[string]any) error {
	for _, ob := range outs {
		if ob == nil || mtsSkip(ob) {
			continue
		}
		if r := MtsBlocked(ob); r != "" {
			return fmt.Errorf("МТС прокси: %s", r)
		}
		ob["detour"] = MtsTag
	}
	return nil
}

// ApplyMtsXray chains an Xray outbound through the MTS HTTP proxy. sockopt.dialerProxy keeps the
// outbound's own streamSettings (XHTTP/TLS/REALITY), unlike the legacy proxySettings.
func ApplyMtsXray(ob map[string]any) {
	st, _ := ob["streamSettings"].(map[string]any)
	if st == nil {
		st = map[string]any{}
		ob["streamSettings"] = st
	}
	so, _ := st["sockopt"].(map[string]any)
	if so == nil {
		so = map[string]any{}
		st["sockopt"] = so
	}
	so["dialerProxy"] = MtsTag
}
