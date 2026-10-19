package engine

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
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
	a.logLocked("qWDTT: клиент завершился: " + reason)
	a.mu.Unlock()
	a.stopAll()
	a.mu.Lock()
	defer a.mu.Unlock()
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

// qwdttRestartFailed: an automatic restart failed before connecting; keep backing off.
func (a *App) qwdttRestartFailed(err error) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	n := a.qwRetry
	if n == 0 || n >= len(qwBackoff) || a.status != "disconnected" {
		a.qwRetry = 0
		return false
	}
	a.scheduleQwRestartLocked(n, err.Error())
	return true
}
