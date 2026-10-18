package engine

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

// Local-only: NOX_SUB_FILE=<decoded subscription> go test -run TestSubPingLocal -v
func TestSubPingLocal(t *testing.T) {
	f := os.Getenv("NOX_SUB_FILE")
	if f == "" {
		t.Skip()
	}
	b, _ := os.ReadFile(f)
	d := t.TempDir()
	a := NewApp(d, d)
	a.binDir = d
	os.Symlink("/workspace/tools/sb/sing-box-1.14.3-linux-amd64/sing-box", filepath.Join(d, "sing-box.exe"))
	os.Symlink("/workspace/xr/xray", filepath.Join(d, "xray.exe"))
	r := a.Import(string(b))
	t.Log(r.Msg, r.Errors)
	a.PingServers(nil)
	for i := 0; i < 150 && a.GetState().Pinging; i++ {
		time.Sleep(200 * time.Millisecond)
	}
	for _, s := range a.GetState().Servers {
		t.Logf("%-28s %-14s %s:%d ping=%d", s.Name, s.Type, s.Host, s.Port, s.Ping)
	}
	t.Log(a.GetLog())
}

func TestSubDumpLocal(t *testing.T) {
	f := os.Getenv("NOX_SUB_FILE")
	if f == "" {
		t.Skip()
	}
	b, _ := os.ReadFile(f)
	d := t.TempDir()
	a := NewApp(d, d)
	a.Import(string(b))
	for _, s := range a.GetState().Servers {
		if s.Port == 2087 || s.Port == 28503 {
			os.WriteFile("/tmp/ob-"+s.ID+".json", s.Outbound, 0o600)
			t.Log(s.Name, "/tmp/ob-"+s.ID+".json")
		}
	}
}

func TestXhttpConnectLocal(t *testing.T) {
	f := os.Getenv("NOX_SUB_FILE")
	if f == "" {
		t.Skip()
	}
	b, _ := os.ReadFile(f)
	d := t.TempDir()
	a := NewApp(d, d)
	a.binDir = d
	os.Symlink("/workspace/tools/sb/sing-box-1.14.3-linux-amd64/sing-box", filepath.Join(d, "sing-box.exe"))
	os.Symlink("/workspace/xr/xray", filepath.Join(d, "xray.exe"))
	for _, f := range []string{"geoip-ru.srs", "geosite-category-ru.srs", "geosite-category-ads-all.srs"} {
		os.Symlink("/workspace/nox/nox2/third_party/windows/"+f, filepath.Join(d, f))
	}
	a.Import(string(b))
	for _, s := range a.GetState().Servers {
		if s.Type == "VLESS XHTTP" && s.Port == 2087 {
			a.Select(s.ID)
		}
	}
	st := a.p.Settings
	st.Mode = "proxy"
	st.ProxyPort = 21081
	a.SaveSettings(st)
	a.Connect()
	for i := 0; i < 100 && a.GetState().Status != "connected"; i++ {
		time.Sleep(200 * time.Millisecond)
		if e := a.GetState().Error; e != "" {
			t.Fatal(e)
		}
	}
	out, _ := exec.Command("curl", "-s", "-m", "15", "-x", "http://127.0.0.1:21081", "https://api.ipify.org").Output()
	t.Logf("status=%s exit ip=%s", a.GetState().Status, out)
	time.Sleep(1500 * time.Millisecond)
	tr := a.GetTraffic()
	t.Log("traffic", tr.DownTotal, tr.UpTotal, tr.Seq)
	a.Disconnect()
	time.Sleep(500 * time.Millisecond)
	t.Log(a.GetLog())
}
