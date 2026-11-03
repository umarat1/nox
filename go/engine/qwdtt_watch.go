package engine

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"os/exec"
	"strings"
	"time"

	"nox/core"
)

// qWDTT restart policy: an unexpected exit of the qwdtt client after it connected is retried
// with backoff instead of dropping the VPN for good.
var (
	qwBackoff   = []time.Duration{2 * time.Second, 4 * time.Second, 8 * time.Second, 16 * time.Second, 30 * time.Second}
	qwStableFor = 2 * time.Minute // a session that lived this long resets the retry counter
)

// qwdttExitReason: exit code/signal plus the known fatal line or the last log lines.
func qwdttExitReason(cmd *exec.Cmd, fatal string, tail []string) string {
	code := "?"
	if ps := cmd.ProcessState; ps != nil {
		code = ps.String() // "exit status 1" / "signal: killed"
	}
	r := code
	if fatal != "" {
		r += "; " + fatal
	} else if len(tail) > 0 {
		t := tail
		if len(t) > 3 {
			t = t[len(t)-3:]
		}
		r += "; " + strings.Join(t, " | ")
	}
	return r
}

// qwdttExited handles the exit of a qwdtt process that had delivered its config.
// Only the *current* process matters: stopAll() clears a.qw before killing it, so exits caused
// by Disconnect / server switch / reconnect after a settings change are ignored. (Before 1.0.12
// the old watcher saw the new session's "connecting" status and tore it down with
// «qWDTT: клиент завершился».)
func (a *App) qwdttExited(cmd *exec.Cmd, reason string, fatal bool, lived time.Duration) {
	a.mu.Lock()
	if a.qw != cmd || (a.status != "connected" && a.status != "connecting") {
		a.mu.Unlock()
		return
	}
	if lived >= qwStableFor {
		a.qwRetry = 0
	}
	n := a.qwRetry
	a.qwHandoff = true // the sing-box watcher must not schedule a second reconnect
	a.logLocked("qWDTT: клиент завершился: " + reason)
	a.mu.Unlock()
	a.stopAll()
	a.mu.Lock()
	defer a.mu.Unlock()
	a.qwHandoff = false
	if a.stopWanted || a.status != "disconnected" {
		return
	}
	if fatal || n >= len(qwBackoff) {
		a.errMsg = "qWDTT: клиент завершился: " + reason
		a.qwRetry = 0
		return
	}
	a.scheduleQwRestartLocked(n, reason)
}

// scheduleQwRestartLocked schedules automatic restart number n+1 (a.mu held).
func (a *App) scheduleQwRestartLocked(n int, reason string) {
	d := qwBackoff[n]
	a.qwRetry = n + 1
	tok := time.Now().UnixNano()
	a.qwToken = tok
	a.errMsg = fmt.Sprintf("qWDTT: клиент завершился (%s) — переподключение через %d с (попытка %d/%d)",
		reason, int(d/time.Second), n+1, len(qwBackoff))
	a.logLocked(a.errMsg)
	go func() {
		time.Sleep(d)
		a.mu.Lock()
		ok := a.qwToken == tok && a.status == "disconnected"
		if ok {
			a.qwToken = 0
		}
		a.mu.Unlock()
		if ok {
			a.Connect()
		}
	}()
}

// qwdttRetryable: password / device / expiry failures will not get better by themselves.
func qwdttRetryable(err error) bool {
	if err == nil {
		return false
	}
	s := err.Error()
	switch {
	case strings.Contains(s, "отменено"):
		return false
	case strings.Contains(s, "неверный пароль"), strings.Contains(s, "другому устройству"):
		return false
	case strings.Contains(s, "истёк"), strings.Contains(s, "деактивирован"):
		return false
	case strings.Contains(s, "нет IPv4"):
		return false
	default:
		return true
	}
}

// qwdttRestartFailed: an automatic restart failed before connecting; keep backing off.
// The first failure (qwRetry == 0) is retried too — a VK hiccup at startup used to
// drop the session for good.
func (a *App) qwdttRestartFailed(err error) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.stopWanted || !qwdttRetryable(err) || a.status != "disconnected" {
		a.qwRetry = 0
		return false
	}
	n := a.qwRetry
	if n >= len(qwBackoff) {
		a.qwRetry = 0
		return false
	}
	a.scheduleQwRestartLocked(n, err.Error())
	return true
}

// noteCoreExit reconnects after sing-box or Xray dies on its own.
// Ignored when the user disconnected, or when the qWDTT watcher is already restarting.
func (a *App) noteCoreExit(reason string) {
	a.mu.Lock()
	wasUp := a.status == "connected" || a.status == "connecting"
	user := a.stopWanted
	handoff := a.qwHandoff || a.qwToken != 0
	a.mu.Unlock()
	if !wasUp || user || handoff {
		return
	}
	a.stopAll()
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.stopWanted || a.qwHandoff || a.qwToken != 0 || a.status != "disconnected" {
		return
	}
	n := a.coreRetry
	if n >= len(qwBackoff) {
		a.errMsg = "Соединение прервано: " + reason
		a.coreRetry = 0
		return
	}
	d := qwBackoff[n]
	a.coreRetry = n + 1
	tok := time.Now().UnixNano()
	a.coreToken = tok
	a.errMsg = fmt.Sprintf("Соединение прервано (%s) — переподключение через %d с (попытка %d/%d)",
		reason, int(d/time.Second), n+1, len(qwBackoff))
	a.logLocked(a.errMsg)
	go func() {
		time.Sleep(d)
		a.mu.Lock()
		ok := a.coreToken == tok && !a.stopWanted && a.status == "disconnected"
		if ok {
			a.coreToken = 0
		}
		a.mu.Unlock()
		if ok {
			a.Connect()
		}
	}()
}

// qwdttHealthLoop restarts a qWDTT session that is still "connected" but has stopped
// passing traffic (the process often stays up while the VK TURN path dies).
func (a *App) qwdttHealthLoop(ctx context.Context, srv core.Server, s core.Settings) {
	port := s.ProxyPort
	if port == 0 {
		port = 2080
	}
	pu, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
	cl := &http.Client{Timeout: 6 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(pu), DisableKeepAlives: true}}
	fails := 0
	var okSince time.Time
	urls := []string{"https://www.gstatic.com/generate_204", "https://cp.cloudflare.com/generate_204", "https://ya.ru/"}
	for {
		select {
		case <-ctx.Done():
			return
		case <-time.After(20 * time.Second):
		}
		good := false
		for _, u := range urls {
			req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
			if err != nil {
				continue
			}
			if r, err := cl.Do(req); err == nil {
				r.Body.Close()
				if r.StatusCode < 500 {
					good = true
					break
				}
			}
			if ctx.Err() != nil {
				return
			}
		}
		if good {
			fails = 0
			if okSince.IsZero() {
				okSince = time.Now()
			}
			if time.Since(okSince) >= qwStableFor {
				a.mu.Lock()
				a.qwRetry = 0
				a.coreRetry = 0
				a.mu.Unlock()
				okSince = time.Now()
			}
			continue
		}
		okSince = time.Time{}
		fails++
		if fails < 3 {
			continue
		}
		pn := a.pingNetwork()
		if pn.tcpPing("1.1.1.1", 443) < 0 && pn.tcpPing("77.88.8.8", 443) < 0 {
			fails = 2
			continue
		}
		a.mu.Lock()
		if a.stopWanted || a.status != "connected" || a.p.Selected != srv.ID {
			a.mu.Unlock()
			return
		}
		n := a.qwRetry
		if n >= len(qwBackoff) {
			a.errMsg = "qWDTT: туннель молчит, переподключение исчерпано"
			a.mu.Unlock()
			return
		}
		a.qwHandoff = true
		a.logLocked("qWDTT: туннель молчит, переподключение")
		a.mu.Unlock()
		a.stopAll()
		a.mu.Lock()
		a.qwHandoff = false
		if a.stopWanted || a.status != "disconnected" {
			a.mu.Unlock()
			return
		}
		a.scheduleQwRestartLocked(n, "туннель молчит")
		a.mu.Unlock()
		return
	}
}
