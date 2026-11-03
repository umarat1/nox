package core

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func adCfg(t *testing.T, s Settings, rd string) (string, []map[string]any, []map[string]any) {
	t.Helper()
	b, err := BuildConfig(map[string]any{"type": "vless", "server": "1.2.3.4", "server_port": 443, "uuid": "11111111-2222-3333-4444-555555555555"}, s, "127.0.0.1:9", rd)
	if err != nil {
		t.Fatal(err)
	}
	var cfg struct {
		DNS   struct{ Rules []map[string]any } `json:"dns"`
		Route struct{ Rules []map[string]any } `json:"route"`
	}
	json.Unmarshal(b, &cfg)
	return string(b), cfg.DNS.Rules, cfg.Route.Rules
}

// 2.4.0: Rutube toggle — hosts from the public filter lists, rejected before RU direct
// (rutube.ru itself is on the direct list and must stay reachable).
func TestAdsRutube(t *testing.T) {
	s := DefaultSettings()
	if !s.AdsRutube {
		t.Fatal("Rutube must be on by default")
	}
	js, dns, route := adCfg(t, s, "")
	for _, h := range []string{"a.rutube.ru", "ssp.rutube.ru", "log.rutube.ru"} {
		if !strings.Contains(js, `"`+h+`"`) {
			t.Fatal("missing", h)
		}
	}
	src := AdSources(s, "")
	for i, v := range src {
		j, _ := json.Marshal(dns[i])
		if dns[i]["action"] != "predefined" {
			t.Fatal("ad rules must lead the DNS rules", i, string(j))
		}
		if v == "rutube" && !strings.Contains(string(j), "ssp.rutube.ru") {
			t.Fatal("AdSources index does not match the DNS rule", i, string(j))
		}
	}
	if len(src) != 6 { // google, analytics, yandex, appmetrica, mailvk, rutube (no ads.srs in "")
		t.Fatal(src)
	}
	rt, ru := -1, -1
	for i, r := range route {
		j, _ := json.Marshal(r)
		if strings.Contains(string(j), `"ssp.rutube.ru"`) && r["action"] == "reject" {
			rt = i
		}
		if strings.Contains(string(j), `"rutube.ru","rutubelist.ru"`) {
			ru = i
		}
	}
	if rt < 0 || ru < 0 || rt > ru {
		t.Fatal("rutube reject must come before RU direct", rt, ru)
	}
	s.AdsRutube = false
	if js, _, _ := adCfg(t, s, ""); strings.Contains(js, "ssp.rutube.ru") {
		t.Fatal("Rutube off but listed")
	}
}

// 2.4.0 allow-list: every ad rule becomes AND(matcher, NOT allow) in DNS and route.
func TestAdsAllowList(t *testing.T) {
	s := DefaultSettings()
	s.AdsAllow = []string{"https://mc.yandex.ru/", " *.log.rutube.ru "}
	_, dns, route := adCfg(t, s, "")
	n := len(AdSources(s, ""))
	for i := 0; i < n; i++ {
		r := dns[i]
		j, _ := json.Marshal(r)
		if r["type"] != "logical" || r["action"] != "predefined" || !strings.Contains(string(j), `"domain_suffix":["mc.yandex.ru","log.rutube.ru"],"invert":true`) {
			t.Fatal("dns rule", i, string(j))
		}
	}
	rej := 0
	for _, r := range route {
		j, _ := json.Marshal(r)
		if r["action"] == "reject" && strings.Contains(string(j), `"invert":true`) && strings.Contains(string(j), "mc.yandex.ru") {
			rej++
		}
	}
	if rej != n {
		t.Fatal("route ad rules with allow-list", rej, n)
	}
}

// The counter parses sing-box's DNS router debug lines.
func TestAdMatchLineShape(t *testing.T) {
	// kept in core so the format assumption is next to AdSources; parser lives in engine
	l := "[3196453375 0ms] dns: match[5] domain_suffix=[a.rutube.ru ssp.rutube.ru log.rutube.ru] => predefined(NXDOMAIN)"
	if !strings.Contains(l, "dns: match[") || !strings.Contains(l, "=> predefined(") {
		t.Fatal()
	}
}

// With a real sing-box binary (SINGBOX=/path/sing-box), the generated config must pass
// `sing-box check`, with and without the allow-list.
func TestAdsConfigSingBoxCheck(t *testing.T) {
	bin := os.Getenv("SINGBOX")
	if bin == "" {
		t.Skip("SINGBOX not set")
	}
	for _, allow := range [][]string{nil, {"mc.yandex.ru"}} {
		s := DefaultSettings()
		s.AdsAllow = allow
		s.Mode = "proxy"
		js, _, _ := adCfg(t, s, "")
		p := filepath.Join(t.TempDir(), "c.json")
		os.WriteFile(p, []byte(js), 0o600)
		if out, err := exec.Command(bin, "check", "-c", p).CombinedOutput(); err != nil {
			t.Fatal(err, string(out))
		}
	}
}
