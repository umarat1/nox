package engine

import (
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestAppFlow(t *testing.T) {
	b, err := os.ReadFile("/workspace/links.txt")
	if err != nil {
		t.Skip()
	}
	d := t.TempDir()
	os.Setenv("LOCALAPPDATA", d)
	a := NewApp("", "")
	a.binDir = d
	os.Symlink("/workspace/vps-pc/dl/sing-box-1.14.3-linux-amd64/sing-box", filepath.Join(d, "sing-box.exe"))
	for _, f := range []string{"geoip-ru.srs", "geosite-category-ru.srs"} {
		os.Symlink("/tmp/rules/"+f, filepath.Join(d, f))
	}
	r := a.Import(string(b))
	t.Log(r.Msg, r.Errors)
	a.PingServers(nil)
	for i := 0; i < 100 && a.GetState().Pinging; i++ {
		time.Sleep(200 * time.Millisecond)
	}
	for _, s := range a.GetState().Servers {
		t.Log(s.Name, s.Type, s.Ping)
	}
	st := a.p.Settings
	st.Mode = "proxy"
	st.ProxyPort = 21080
	a.SaveSettings(st)
	best := a.p.Servers[0]
	for _, x := range a.p.Servers {
		if x.Ping > 0 && (best.Ping <= 0 || x.Ping < best.Ping) {
			best = x
		}
	}
	a.Select(best.ID)
	a.Connect()
	for i := 0; i < 100 && a.GetState().Status == "connecting"; i++ {
		time.Sleep(200 * time.Millisecond)
	}
	s := a.GetState()
	t.Log("status", s.Status, s.Error)
	if s.Status != "connected" {
		t.Fatal(a.GetLog())
	}
	pu, _ := url.Parse("http://127.0.0.1:21080")
	cl := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(pu)}}
	resp, err := cl.Get("https://ya.ru/")
	if err != nil {
		t.Fatal(err)
	}
	t.Log("ya.ru via proxy (RU bypass on):", resp.StatusCode)
	r2, err := cl.Get("https://ifconfig.me/ip")
	if err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 64)
	n, _ := r2.Body.Read(buf)
	t.Log("exit ip via proxy:", string(buf[:n]))
	time.Sleep(2500 * time.Millisecond)
	tr := a.GetTraffic()
	t.Log("traffic", tr.DownTotal, tr.UpTotal, len(tr.Hist))
	a.Disconnect()
	t.Log("after", a.GetState().Status)
}
