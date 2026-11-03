package core

import (
	"encoding/json"
	"testing"
)

// 2.3.2 «Раздача через точку доступа»: off by default; when on, the mixed inbound listens on
// all interfaces at 10808 and only RFC 1918 / loopback clients pass (the first route rule).
func TestHotspotShare232(t *testing.T) {
	s := DefaultSettings()
	if s.AllowLAN || s.ProxyPort != 10808 {
		t.Fatalf("defaults: allowLan=%v port=%d", s.AllowLAN, s.ProxyPort)
	}
	type cfgT struct {
		Inbounds []map[string]any
		Route    struct{ Rules []map[string]any } `json:"route"`
	}
	build := func(s Settings) cfgT {
		b, err := BuildConfig(map[string]any{"type": "vless", "server": "1.2.3.4", "server_port": 443}, s, "127.0.0.1:9", "")
		if err != nil {
			t.Fatal(err)
		}
		var c cfgT
		json.Unmarshal(b, &c)
		return c
	}
	off := build(s)
	if off.Inbounds[0]["listen"] != "127.0.0.1" {
		t.Fatalf("off: %v", off.Inbounds[0])
	}
	for _, r := range off.Route.Rules {
		if r["action"] == "reject" && r["inbound"] != nil {
			t.Fatal("off: no source filter expected")
		}
	}
	s.AllowLAN = true
	s.ShareUser, s.SharePass = "pp1234", "secret"
	on := build(s)
	m := on.Inbounds[0]
	if m["type"] != "mixed" || m["listen"] != "0.0.0.0" || m["listen_port"].(float64) != 10808 || m["users"] == nil {
		t.Fatalf("on: %v", m)
	}
	r := on.Route.Rules[0]
	j, _ := json.Marshal(r)
	// 2.3.3: logical AND — only mixed-in from a non-private source is rejected (TUN untouched)
	if string(j) != `{"action":"reject","mode":"and","rules":[{"inbound":["mixed-in"]},{"invert":true,"source_ip_cidr":["10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","127.0.0.0/8","::1/128"]}],"type":"logical"}` {
		t.Fatalf("first rule: %s", j)
	}
	for _, rr := range on.Route.Rules {
		if rr["invert"] == true {
			t.Fatalf("top-level invert would reject TUN traffic: %v", rr)
		}
	}
}

// 2.3.3: AnyTLS must never get tcp_fast_open (sing-box refuses to start).
func TestAnyTLSNoTFO233(t *testing.T) {
	s := DefaultSettings()
	b, err := BuildConfig(map[string]any{"type": "anytls", "server": "1.2.3.4", "server_port": 443, "password": "x", "tcp_fast_open": true}, s, "127.0.0.1:9", "")
	if err != nil {
		t.Fatal(err)
	}
	var c struct{ Outbounds []map[string]any }
	json.Unmarshal(b, &c)
	if _, ok := c.Outbounds[0]["tcp_fast_open"]; ok {
		t.Fatalf("anytls tfo: %v", c.Outbounds[0])
	}
}
