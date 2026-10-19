package engine

import (
	"os/exec"
	"strings"
	"testing"
	"time"
)

func exitedCmd(t *testing.T, sh string) *exec.Cmd {
	c := exec.Command("sh", "-c", sh)
	c.Run()
	return c
}

// A qwdtt killed by Disconnect/reconnect must not tear down the session that replaced it.
func TestQwdttStaleExitIgnored(t *testing.T) {
	a := NewApp(t.TempDir(), t.TempDir())
	old := exitedCmd(t, "exit 0")
	cur := exitedCmd(t, "exit 0")
	a.mu.Lock()
	a.qw, a.status = cur, "connecting" // new session already started
	a.mu.Unlock()
	a.qwdttExited(old, "signal: killed", false, time.Second)
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.status != "connecting" || a.qw != cur || a.errMsg != "" {
		t.Fatalf("stale exit touched new session: status=%s err=%q", a.status, a.errMsg)
	}
}

func TestQwdttExitReasonAndBackoff(t *testing.T) {
	saved := qwBackoff
	qwBackoff = []time.Duration{time.Hour, time.Hour}
	defer func() { qwBackoff = saved }()
	a := NewApp(t.TempDir(), t.TempDir())
	cur := exitedCmd(t, "exit 3")
	r := qwdttExitReason(cur, "", []string{"a", "b", "turn: allocate failed", "dial vk: timeout"})
	if !strings.Contains(r, "exit status 3") || !strings.Contains(r, "dial vk: timeout") || strings.Contains(r, "a |") {
		t.Fatalf("reason %q", r)
	}
	a.mu.Lock()
	a.qw, a.status = cur, "connected"
	a.mu.Unlock()
	a.qwdttExited(cur, r, false, time.Second)
	a.mu.Lock()
	if a.status != "disconnected" || a.qwToken == 0 || a.qwRetry != 1 || !strings.Contains(a.errMsg, "попытка 1/2") || !strings.Contains(a.errMsg, "exit status 3") {
		t.Fatalf("status=%s tok=%d retry=%d err=%q", a.status, a.qwToken, a.qwRetry, a.errMsg)
	}
	a.mu.Unlock()
	a.Disconnect() // user stop cancels the pending restart
	a.mu.Lock()
	if a.qwToken != 0 || a.qwRetry != 0 {
		t.Fatal("Disconnect kept pending restart")
	}
	// retries exhausted → final error, no restart
	a.qw, a.status, a.qwRetry = cur, "connected", 2
	a.mu.Unlock()
	a.qwdttExited(cur, r, false, time.Second)
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.qwToken != 0 || !strings.HasPrefix(a.errMsg, "qWDTT: клиент завершился: exit status 3") {
		t.Fatalf("err=%q tok=%d", a.errMsg, a.qwToken)
	}
}
