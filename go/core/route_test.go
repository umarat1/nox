package core

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
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
	// 2.3.3: never an implicit smux (Xray SS/VMess inbounds drop it); a link's own multiplex stays
	if err != nil || strings.Contains(string(vm), `"multiplex"`) {
		t.Fatal("no implicit mux", string(vm))
	}
	ss, _ := BuildConfig(map[string]any{"type": "shadowsocks", "server": "1.2.3.4", "server_port": 8388, "method": "chacha20-ietf-poly1305", "password": "x"}, s, "127.0.0.1:9", "")
	if strings.Contains(string(ss), `"multiplex"`) {
		t.Fatal("ss: no implicit mux", string(ss))
	}
	own, _ := BuildConfig(map[string]any{"type": "shadowsocks", "server": "1.2.3.4", "server_port": 8388, "method": "chacha20-ietf-poly1305", "password": "x", "multiplex": map[string]any{"enabled": true}}, s, "127.0.0.1:9", "")
	if !strings.Contains(string(own), `"multiplex"`) {
		t.Fatal("link multiplex must be kept", string(own))
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

// 2.2.1: ad hosts are rejected before any direct rule (YouTube direct included) and get
// NXDOMAIN from DNS; video hosts are never on the list.
func TestBlockAdsDirectAndDNS(t *testing.T) {
	s := DefaultSettings()
	s.BlockAds = true
	s.DirectDomains = []string{"youtube.com", "googlevideo.com"}
	rd := t.TempDir()
	os.WriteFile(filepath.Join(rd, "geosite-ads-other.srs"), []byte("x"), 0o644)
	b, err := BuildConfig(map[string]any{"type": "vless", "server": "1.2.3.4", "server_port": 443}, s, "127.0.0.1:9", rd)
	if err != nil {
		t.Fatal(err)
	}
	var cfg struct {
		DNS   struct{ Rules []map[string]any } `json:"dns"`
		Route struct{ Rules []map[string]any } `json:"route"`
	}
	json.Unmarshal(b, &cfg)
	find := func(rs []map[string]any, want string) int {
		for i, r := range rs {
			if j, _ := json.Marshal(r); strings.Contains(string(j), want) {
				return i
			}
		}
		return -1
	}
	ads, set, yt := find(cfg.Route.Rules, `"doubleclick.net"`), find(cfg.Route.Rules, `"rule_set":"ads"`), find(cfg.Route.Rules, `"youtube.com","googlevideo.com"],"outbound":"direct"`)
	if ads < 0 || set < 0 || yt < 0 || ads > yt || set > yt || cfg.Route.Rules[ads]["action"] != "reject" {
		t.Fatal(ads, set, yt, string(b))
	}
	d0, d1, dy := find(cfg.DNS.Rules, `"doubleclick.net"`), find(cfg.DNS.Rules, `"rule_set":"ads"`), find(cfg.DNS.Rules, `"youtube.com"`)
	// 2.4.0: one DNS rule per vendor, «Прочие сети» (rule_set) last
	if d0 != 0 || d1 != len(AdSources(s, rd))-1 || dy <= d1 || cfg.DNS.Rules[0]["rcode"] != "NXDOMAIN" {
		t.Fatal(d0, d1, dy, string(b))
	}
	for _, v := range []string{"youtube.com", "googlevideo.com", "ytimg.com", "ggpht.com", "googleapis.com", "gstatic.com"} {
		all := DefaultSettings()
		all.AdsAnalytics, all.AdsAppMetrica = true, true
		for _, a := range AdSuffixesFor(all) {
			if a == v || strings.HasSuffix(v, "."+a) {
				t.Fatal("video host blocked", v)
			}
		}
	}
	s.BlockAds = false
	off, _ := BuildConfig(map[string]any{"type": "vless", "server": "1.2.3.4", "server_port": 443}, s, "127.0.0.1:9", "")
	if strings.Contains(string(off), "doubleclick") || strings.Contains(string(off), "NXDOMAIN") {
		t.Fatal("ads rules without the toggle")
	}
}

// 2.3.1: vendor sub-toggles; ads are rejected before «Россия напрямую»; services stay reachable.
func TestAdTogglesBeforeRU(t *testing.T) {
	s := DefaultSettings()
	s.BlockAds = true
	s.AdsGoogle = false
	s.AdsAnalytics, s.AdsAppMetrica = false, false
	b, err := BuildConfig(map[string]any{"type": "vless", "server": "1.2.3.4", "server_port": 443}, s, "127.0.0.1:9", t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var cb bytes.Buffer
	json.Compact(&cb, b)
	js := cb.String()
	if strings.Contains(js, "doubleclick.net") || !strings.Contains(js, "an.yandex.ru") || !strings.Contains(js, "ad.mail.ru") {
		t.Fatal("google off / yandex+mail on", js)
	}
	if strings.Contains(js, "appmetrica") || strings.Contains(js, "google-analytics") {
		t.Fatal("optional lists must be off when switched off")
	}
	ru := strings.LastIndex(js, `"domain_suffix":["ru","su"`)
	if ru < 0 || strings.LastIndex(js, `"an.yandex.ru"`) > ru {
		t.Fatal("ad reject must come before RU direct")
	}
	all := DefaultSettings()
	all.AdsAnalytics, all.AdsAppMetrica = true, true
	keep := []string{"yandex.ru", "ya.ru", "mail.yandex.ru", "passport.yandex.ru", "api-maps.yandex.ru", "clck.yandex.ru",
		"startup.mobile.yandex.net", "mail.ru", "e.mail.ru", "r.mail.ru", "account.mail.ru", "vk.com", "id.vk.com", "login.vk.com",
		"api.vk.com", "ok.ru", "google.com", "www.google.com", "accounts.google.com", "mail.google.com", "play.google.com",
		"android.clients.google.com", "mtalk.google.com", "fcm.googleapis.com", "youtube.com", "googlevideo.com", "ytimg.com",
		"rutube.ru", "static.rutube.ru", "pic.rutube.ru", "rutubelist.ru"}
	for _, h := range keep {
		for _, a := range AdSuffixesFor(all) {
			if h == a || strings.HasSuffix(h, "."+a) {
				t.Fatal("service host blocked", h, a)
			}
		}
	}
}

// 2.3.2: fresh-install defaults — routing/ads/auto toggles on, IPv6 off.
func TestDefaults232(t *testing.T) {
	d := DefaultSettings()
	if !d.DirectRU || !d.RuApps || !d.BlockAds || !d.AdsGoogle || !d.AdsYandex || !d.AdsMailVK || !d.AdsOther ||
		!d.AdsAnalytics || !d.AdsAppMetrica || !d.AutoBest || !d.FastDial || !d.AutoConn || !d.Autostart {
		t.Fatalf("defaults must be on: %+v", d)
	}
	if d.IPv6 {
		t.Fatal("IPv6 must stay off")
	}
}
