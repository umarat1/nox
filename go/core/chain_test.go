package core

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestChain(t *testing.T) {
	a, _ := ParseLink("socks://u:p@1.1.1.1:1080#A")
	b, _ := ParseLink("anytls://pw@2.2.2.2:443?sni=x.com#B")
	c, _ := ParseLink("trojan://pw@3.3.3.3:443?sni=y.com#C")
	ch, err := MakeChain("", []Server{a, b, c})
	if err != nil || ch.Name != "A → B → C" {
		t.Fatal(err, ch.Name)
	}
	var m map[string]any
	json.Unmarshal(ch.Outbound, &m)
	cfg, err := BuildConfig(m, Settings{}, "127.0.0.1:1", "")
	if err != nil {
		t.Fatal(err)
	}
	s := string(cfg)
	if !strings.Contains(s, `"detour": "c1"`) || !strings.Contains(s, `"tag": "c0"`) {
		t.Fatal(s)
	}
	json.Unmarshal(ch.Outbound, &m)
	if _, err := TestConfig(m, 1234); err != nil {
		t.Fatal(err)
	}
	for _, l := range []string{"juicity://u:p@h:1#j", "mierus://u:p@h?port=1&protocol=TCP", "snell://psk@h:1?version=4",
		"shadowquic://u:p@h:1?sni=x", "naive+https://u:p@h:443", "trusttunnel://u:p@h:443?quic=1"} {
		s, err := ParseLink(l)
		if err != nil || !IsExt(s.Outbound) {
			t.Fatal(l, err)
		}
	}
}
