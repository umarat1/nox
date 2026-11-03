package engine

import (
	"encoding/json"
	"testing"

	"nox/core"
)

// 2.3.3: NaiveProxy (https) and mieru (TCP) are allowed under «МТС прокси»; UDP-only stay blocked.
func TestExtMtsBlocked233(t *testing.T) {
	cases := []struct {
		kind string
		cfg  map[string]any
		ok   bool
	}{
		{"naive", map[string]any{"scheme": "https"}, true},
		{"naive", map[string]any{"scheme": "quic"}, false},
		{"mihomo", map[string]any{"type": "mieru", "transport": "TCP"}, true},
		{"mihomo", map[string]any{"type": "mieru", "transport": "UDP"}, false},
		{"mihomo", map[string]any{"type": "shadowquic"}, false},
		{"mihomo", map[string]any{"type": "trusttunnel"}, false},
		{"juicity", map[string]any{}, false},
	}
	for _, c := range cases {
		if got := extMtsBlocked(c.kind, c.cfg) == ""; got != c.ok {
			t.Errorf("%s %v: allowed=%v want %v", c.kind, c.cfg, got, c.ok)
		}
	}
}

// 2.3.3: AutoBest under «МТС прокси» only picks what the phone lists (Naive/mieru/AnyTLS/VLESS/proxies).
func TestMtsAutoBest233(t *testing.T) {
	srv := func(id, typ, ob string, ping int) core.Server {
		return core.Server{ID: id, Type: typ, Outbound: json.RawMessage(ob), Ping: ping}
	}
	list := []core.Server{
		srv("ss", "Shadowsocks", `{"type":"shadowsocks","server":"a"}`, 10),
		srv("tr", "Trojan", `{"type":"trojan","server":"a"}`, 11),
		srv("hy", "Hysteria2", `{"type":"hysteria2","server":"a"}`, 5),
		srv("nq", "Naive", `{"type":"_ext","kind":"naive","cfg":{"scheme":"quic"}}`, 6),
		srv("mi", "Mieru", `{"type":"_ext","kind":"mihomo","cfg":{"type":"mieru","transport":"TCP"}}`, 55),
		srv("nv", "Naive", `{"type":"_ext","kind":"naive","cfg":{"scheme":"https"}}`, 70),
		srv("at", "AnyTLS", `{"type":"anytls","server":"a"}`, 90),
		srv("vx", "VLESS XHTTP", `{"type":"_xray","xray":{"protocol":"vless"}}`, 60),
	}
	want := map[string]bool{"mi": true, "nv": true, "at": true, "vx": true}
	for _, s := range list {
		if got := mtsListed(s); got != want[s.ID] {
			t.Errorf("mtsListed(%s)=%v", s.ID, got)
		}
	}
	a := &App{}
	a.p.Servers = list
	a.p.Selected = "ss"
	a.p.Settings.MtsProxy = true
	if id := a.bestIDLocked(40); id != "mi" {
		t.Fatalf("МТС AutoBest picked %q, want mi (fastest listed)", id)
	}
	a.p.Settings.MtsProxy = false
	if id := a.bestIDLocked(0); id != "hy" {
		t.Fatalf("direct AutoBest picked %q, want hy", id)
	}
}
