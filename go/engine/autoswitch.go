package engine

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"nox/core"
)

// regionOf returns the ISO code from a flag emoji in the server name ("🇩🇪 Германия" -> "DE").
func regionOf(name string) string {
	r := []rune(name)
	for i := 0; i+1 < len(r); i++ {
		if r[i] >= 0x1F1E6 && r[i] <= 0x1F1FF && r[i+1] >= 0x1F1E6 && r[i+1] <= 0x1F1FF {
			return string(rune('A'+r[i]-0x1F1E6)) + string(rune('A'+r[i+1]-0x1F1E6))
		}
	}
	return ""
}

// nextServer: same country with another protocol first, then other countries by lowest ping.
// Skips the current server, balancers, qWDTT, SSTP and known-dead servers.
func nextServer(all []core.Server, cur core.Server) *core.Server {
	reg := regionOf(cur.Name)
	var same, other []core.Server
	for _, s := range all {
		if s.ID == cur.ID || s.Type == core.BalancerLabel || s.Type == "qWDTT" || core.IsFullTunnel(s.Outbound) || s.Ping == -1 {
			continue
		}
		if s.SubID == cur.SubID && s.Host == cur.Host && s.Port == cur.Port && s.Type == cur.Type {
			continue // duplicate of the failing one
		}
		if reg != "" && regionOf(s.Name) == reg && s.Type != cur.Type {
			same = append(same, s)
		} else {
			other = append(other, s)
		}
	}
	by := func(l []core.Server) {
		sort.SliceStable(l, func(i, j int) bool {
			pi, pj := l[i].Ping, l[j].Ping
			if (pi > 0) != (pj > 0) {
				return pi > 0
			}
			return pi < pj
		})
	}
	by(same)
	by(other)
	if len(same) > 0 {
		return &same[0]
	}
	if len(other) > 0 {
		return &other[0]
	}
	return nil
}

// autoSwitchLoop (Android «Автопереключение при блокировке»): while connected, every ~20 s
// check generate_204 through the tunnel; after 3 failures in a row (while the direct
// internet works) switch to the next working server, at most once per 60 s.
func (a *App) autoSwitchLoop(ctx context.Context, srv core.Server, s core.Settings) {
	if !s.AutoSwitch || srv.Type == core.BalancerLabel || srv.Type == "qWDTT" {
		return // qWDTT is restarted in place (qwdttHealthLoop); switching away looked like a disconnect
	}
	port := s.ProxyPort
	if port == 0 {
		port = 2080
	}
	pu, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
	cl := &http.Client{Timeout: 6 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(pu), DisableKeepAlives: true}}
	fails := 0
	for {
		select {
		case <-ctx.Done():
			return
		case <-time.After(20 * time.Second):
		}
		req, _ := http.NewRequestWithContext(ctx, "GET", "https://www.gstatic.com/generate_204", nil)
		if r, err := cl.Do(req); err == nil {
			r.Body.Close()
			fails = 0
			continue
		}
		if ctx.Err() != nil {
			return
		}
		fails++
		if fails < 3 {
			continue
		}
		pn := a.pingNetwork()
		if pn.tcpPing("1.1.1.1", 443) < 0 && pn.tcpPing("77.88.8.8", 443) < 0 {
			fails = 2 // no internet at all: not the server's fault, keep watching
			continue
		}
		a.mu.Lock()
		if time.Since(a.lastSwitch) < 60*time.Second || a.p.Selected != srv.ID {
			a.mu.Unlock()
			continue
		}
		next := nextServer(a.p.Servers, srv)
		if next == nil {
			a.mu.Unlock()
			a.log("автопереключение: нет другого рабочего сервера")
			fails = 0
			continue
		}
		a.lastSwitch = time.Now()
		for i := range a.p.Servers {
			if a.p.Servers[i].ID == srv.ID {
				a.p.Servers[i].Ping = -1
			}
		}
		a.notice = "Автопереключение: «" + strings.TrimSpace(srv.Name) + "» не отвечал, переключено на «" + strings.TrimSpace(next.Name) + "»"
		a.mu.Unlock()
		a.log(a.notice)
		a.Select(next.ID) // reconnects (cancels this loop)
		return
	}
}
