package engine

import (
	"os"
	"path/filepath"
	"testing"
)

// 2.3.2: new defaults only for fresh installs; existing settings kept; changes recorded in Touched.
func TestDefaults232Migration(t *testing.T) {
	d := t.TempDir()
	a := NewApp(d, d)
	if !a.p.Settings.BlockAds || !a.p.Settings.AutoConn || a.p.Settings.IPv6 || a.p.SetVer < 232 {
		t.Fatalf("fresh: %+v setVer %d", a.p.Settings, a.p.SetVer)
	}
	d2 := t.TempDir()
	os.WriteFile(filepath.Join(d2, "state.json"), []byte(`{"setVer":128,"settings":{"mode":"tun","directRu":true,"ruApps":true,"blockAds":false,"autoConnect":false,"autoBest":true}}`), 0o600)
	b := NewApp(d2, d2)
	if b.p.Settings.BlockAds || b.p.Settings.AutoConn || b.p.SetVer != 232 {
		t.Fatalf("upgrade must keep user values: %+v", b.p.Settings)
	}
	s := b.p.Settings
	s.BlockAds = true
	b.SaveSettings(s)
	if !b.p.Touched["blockAds"] || b.p.Touched["autoConnect"] {
		t.Fatalf("touched: %v", b.p.Touched)
	}
}
