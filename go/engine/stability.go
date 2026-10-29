package engine

import (
	"context"
	"net/http"
	"sync"
	"time"

	"nox/core"
)

// ExternalStop marks a system revoke (another VPN, user toggle in Android settings)
// so the core watchdog does not immediately dial again.
func (a *App) ExternalStop(msg string) {
	a.mu.Lock()
	a.stopWanted = true
	if msg != "" {
		a.errMsg = msg
	}
	a.mu.Unlock()
}

// UnderlyingNetworkChanged is the physical default network (wifi ↔ mobile).
// The first observation is recorded; a later change while the tunnel is up
// reconnects, after a short pause so a flap does not stack dials. 2.2.0: so does the
// same network returning after a loss ("" in between).
func (a *App) UnderlyingNetworkChanged(name string) {
	if !a.wantRebind(name) {
		return
	}
	go func() {
		time.Sleep(800 * time.Millisecond)
		a.mu.Lock()
		ok := !a.stopWanted && (a.status == "connected" || a.status == "connecting") && a.lastUnder == name
		a.mu.Unlock()
		if !ok {
			return
		}
		a.log("сеть сменилась (" + name + ") — переподключение")
		a.Disconnect()
		a.Connect()
	}()
}

func (a *App) wantRebind(name string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if name == "" {
		// 2.2.0: signal lost (tunnel, lift, roaming). Remember it so the same network
		// coming back also reconnects at once instead of waiting for dead sockets to time out.
		if a.lastUnder != "" {
			a.underLost = true
		}
		return false
	}
	prev, lost := a.lastUnder, a.underLost
	a.lastUnder, a.underLost = name, false
	if prev == "" || (prev == name && !lost) {
		return false
	}
	if a.stopWanted || (a.status != "connected" && a.status != "connecting") {
		return false
	}
	return true
}

// coreWatch restarts sing-box when the local API stops answering. A dead remote
// server still answers /version on loopback, so this does not flap on a blocked node.
func (a *App) coreWatch(ctx context.Context) {
	if a.clashAddr == "" {
		return
	}
	cl := &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{Proxy: nil}}
	fails := 0
	for {
		select {
		case <-ctx.Done():
			return
		case <-time.After(20 * time.Second):
		}
		req, err := http.NewRequestWithContext(ctx, "GET", "http://"+a.clashAddr+"/version", nil)
		if err != nil {
			return
		}
		r, err := cl.Do(req)
		if err == nil {
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
		a.mu.Lock()
		up := a.status == "connected" && !a.stopWanted
		a.mu.Unlock()
		if !up {
			return
		}
		a.log("ядро не отвечает — перезапуск")
		a.noteCoreExit("ядро не отвечает")
		return
	}
}

// pingFresh measures TCP handshakes after a refresh. It does not run the URL
// test and does not mark a server dead, so the refresh call returns as soon as
// the list is saved. Anything still running after 3s is left as it was.
func (a *App) pingFresh(subID string) {
	a.mu.Lock()
	if a.pinging {
		a.mu.Unlock()
		return
	}
	var list []core.Server
	for _, s := range a.p.Servers {
		if subID != "" && s.SubID != subID {
			continue
		}
		if s.Type == core.BalancerLabel {
			continue
		}
		list = append(list, s)
	}
	a.mu.Unlock()
	if len(list) == 0 {
		return
	}
	pn := a.pingNetwork()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var wg sync.WaitGroup
	sem := make(chan struct{}, 32)
	for _, s := range list {
		if ctx.Err() != nil {
			break
		}
		s := s
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				return
			}
			defer func() { <-sem }()
			if ms := pn.tcpPing(s.Host, s.Port); ms > 0 {
				a.setPingQuiet(s.ID, ms)
			}
		}()
	}
	wg.Wait()
}
