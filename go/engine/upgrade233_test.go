package engine

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"nox/core"
)

// 2.3.3 audit: upgrading over 2.2.6 / 2.3.1 / 2.3.2 keeps the user's settings (incl. the old
// «Разрешить из локальной сети» = allowLan), and the resulting config never rejects TUN traffic
// and never adds an implicit smux.
func TestUpgrade233KeepsSettings(t *testing.T) {
	for _, st := range []string{
		`{"setVer":128,"settings":{"mode":"tun","directRu":true,"ruApps":false,"allowLan":true,"fastDial":true,"blockAds":false,"autoConnect":false,"autostart":false,"mtsProxy":false,"proxyPort":10808}}`,
		`{"setVer":128,"settings":{"mode":"tun","directRu":false,"ruApps":true,"allowLan":false,"fastDial":false,"blockAds":true,"adsGoogle":false,"autoConnect":true,"mtsProxy":true,"proxyPort":10808}}`,
		`{"setVer":232,"settings":{"mode":"tun","directRu":true,"ruApps":true,"allowLan":true,"fastDial":true,"blockAds":true,"adsAnalytics":true,"adsAppMetrica":true,"autoConnect":true,"autostart":true,"autoDl":"wifi","proxyPort":10808},"touched":{"blockAds":true}}`,
	} {
		d := t.TempDir()
		os.WriteFile(filepath.Join(d, "state.json"), []byte(st), 0o600)
		a := NewApp(d, d)
		var in struct{ Settings map[string]any }
		json.Unmarshal([]byte(st), &in)
		got, _ := json.Marshal(a.p.Settings)
		var out map[string]any
		json.Unmarshal(got, &out)
		for k, v := range in.Settings {
			if out[k] != v {
				t.Errorf("%s: %s=%v after upgrade, was %v", st[:30], k, out[k], v)
			}
		}
		if a.p.SetVer < 232 {
			t.Errorf("setVer %d", a.p.SetVer)
		}
		cfg, err := core.BuildConfig(map[string]any{"type": "shadowsocks", "server": "1.2.3.4", "server_port": 8388, "method": "chacha20-ietf-poly1305", "password": "x"}, a.p.Settings, "127.0.0.1:9", "")
		if err != nil {
			t.Fatal(err)
		}
		js := string(cfg)
		if strings.Contains(js, `"multiplex"`) {
			t.Error("implicit multiplex")
		}
		var c struct {
			Route struct{ Rules []map[string]any }
		}
		json.Unmarshal(cfg, &c)
		for _, r := range c.Route.Rules {
			if r["invert"] == true {
				t.Errorf("top-level invert rule (rejects TUN): %v", r)
			}
		}
	}
}
