package engine

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"nox/core"
)

func TestAdMatchSrc(t *testing.T) {
	s := core.DefaultSettings()
	s.BlockAds = true
	sigs := core.AdSigs(s, "")
	cases := map[string]string{
		"[1 0ms] dns: match[5] domain_suffix=[a.rutube.ru ssp.rutube.ru log.rutube.ru] => predefined(NXDOMAIN)": "rutube",
		"[2 1ms] router: match[3] domain_suffix=[a.rutube.ru ssp.rutube.ru log.rutube.ru] => reject":            "rutube",
		"[3 0ms] dns: match[5] domain_suffix=[a.rutube.ru ssp.rutube.ru log.rutube.ru] => route(direct)":        "",
		"[4 0ms] router: match[9] network=udp port=443 => reject":                                               "",
		"[5 0ms] dns: lookup succeed for x":                                                                     "",
	}
	for l, want := range cases {
		if got := adMatchSrc(l, sigs); got != want {
			t.Errorf("%q: %q want %q", l, got, want)
		}
	}
}

func tfreePort(t *testing.T) int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

// End to end with a real sing-box (SINGBOX=/path): a connection to an ad host through the
// local proxy is rejected and the clash /logs stream gives a line adMatchSrc attributes.
func TestAdCountSingBox(t *testing.T) {
	bin := os.Getenv("SINGBOX")
	if bin == "" {
		t.Skip("SINGBOX not set")
	}
	s := core.DefaultSettings()
	s.BlockAds, s.Mode, s.ProxyPort = true, "proxy", tfreePort(t)
	clash := fmt.Sprintf("127.0.0.1:%d", tfreePort(t))
	cfg, err := core.BuildConfig(map[string]any{"type": "vless", "server": "127.0.0.1", "server_port": 9, "uuid": "11111111-2222-3333-4444-555555555555"}, s, clash, "")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	p := filepath.Join(dir, "c.json")
	os.WriteFile(p, cfg, 0o600)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, "run", "-c", p, "-D", dir)
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	got := make(chan string, 1)
	go func() {
		for ctx.Err() == nil {
			req, _ := http.NewRequestWithContext(ctx, "GET", "http://"+clash+"/logs?level=debug", nil)
			r, err := (&http.Client{Transport: &http.Transport{Proxy: nil}}).Do(req)
			if err != nil {
				time.Sleep(100 * time.Millisecond)
				continue
			}
			sc := bufio.NewScanner(r.Body)
			for sc.Scan() {
				var e struct{ Payload string }
				json.Unmarshal(sc.Bytes(), &e)
				if src := adMatchSrc(e.Payload, core.AdSigs(s, "")); src != "" {
					got <- src + " | " + e.Payload
					r.Body.Close()
					return
				}
			}
			r.Body.Close()
		}
	}()
	pc := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(mustURL(fmt.Sprintf("http://127.0.0.1:%d", s.ProxyPort)))}}
	deadline := time.After(10 * time.Second)
	tick := time.NewTicker(500 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-tick.C:
			go pc.Get("http://ssp.rutube.ru/")
			continue
		case l := <-got:
			t.Log(l)
			if l[:6] != "rutube" {
				t.Fatal(l)
			}
			cmd.Process.Kill()
			return
		case <-deadline:
			cmd.Process.Kill()
			t.Fatal("no ad match line in /logs")
		}
	}
}

func mustURL(s string) *url.URL { u, _ := url.Parse(s); return u }
