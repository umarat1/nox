package core

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestCleanDomains(t *testing.T) {
	got := cleanDomains([]string{" https://Site.RU/path ", "*.example.com", ".рф", "президент.рф", "a.b:8080", "x y", "site.ru"})
	want := []string{"site.ru", "example.com", "xn--p1ai", "xn--d1abbgf6aiiy.xn--p1ai", "a.b"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatal(got)
	}
}

func TestRoutingRules(t *testing.T) {
	s := DefaultSettings()
	s.ProxyDomains = []string{"kinopoisk.ru"}
	s.DirectDomains = []string{"example.org"}
	b, err := BuildConfig(map[string]any{"type": "vless", "server": "1.2.3.4", "server_port": 443}, s, "127.0.0.1:9", "")
	if err != nil {
		t.Fatal(err)
	}
	var cfg struct {
		Route struct{ Rules []map[string]any } `json:"route"`
	}
	json.Unmarshal(b, &cfg)
	idx := func(want string) int {
		for i, r := range cfg.Route.Rules {
			if j, _ := json.Marshal(r); strings.Contains(string(j), want) {
				return i
			}
		}
		return -1
	}
	priv, px, dir, ru := idx(`"ip_is_private":true`), idx(`"kinopoisk.ru"],"outbound":"proxy"`), idx(`"example.org"],"outbound":"direct"`), idx(`"gosuslugi.ru"`)
	if priv < 0 || px < 0 || dir < 0 || ru < 0 || !(priv < px && px < ru && dir < ru) {
		t.Fatal(priv, px, dir, ru, string(b))
	}
	s.DirectRU = false
	s.FastDial = true
	b, err = BuildConfig(map[string]any{"type": "vless", "server": "1.2.3.4", "server_port": 443}, s, "127.0.0.1:9", "")
	if err != nil {
		t.Fatal(err)
	}
	js := string(b)
	for _, d := range []string{"ivi.ru", "ivi.tv", "ivicdn.tv", "tivision.ru"} {
		if !strings.Contains(js, d) {
			t.Fatal("ivi not direct", d)
		}
	}
	if !strings.Contains(js, `"tcp_fast_open": true`) {
		t.Fatal("tfo", js)
	}
	vm, err := BuildConfig(map[string]any{"type": "vmess", "server": "1.2.3.4", "server_port": 443}, s, "127.0.0.1:9", "")
	if err != nil || !strings.Contains(string(vm), `"multiplex"`) {
		t.Fatal("mux", string(vm))
	}
	s.FastDial = false
	off, err := BuildConfig(map[string]any{"type": "vless", "server": "1.2.3.4", "server_port": 443, "flow": "xtls-rprx-vision"}, s, "127.0.0.1:9", "")
	if err != nil || strings.Contains(string(off), "tcp_fast_open") || strings.Contains(string(off), "multiplex") {
		t.Fatal("fast dial off", string(off))
	}
	for _, d := range []string{"xn--p1ai", "nalog.ru", "ya.ru", "vk.com", "max.ru", "wildberries.ru", "ivi.tv"} {
		found := false
		for _, x := range RuSuffixes {
			found = found || x == d
		}
		if !found {
			t.Fatal("missing", d)
		}
	}
}
