package engine

import "testing"

func TestWantRebindOnlyWhenTunnelUpAndNameChanges(t *testing.T) {
	a := NewApp(t.TempDir(), t.TempDir())
	if a.wantRebind("wlan0") {
		t.Fatal("first sighting while down")
	}
	a.mu.Lock()
	a.status = "connected"
	a.mu.Unlock()
	if a.wantRebind("wlan0") {
		t.Fatal("same network")
	}
	if !a.wantRebind("rmnet0") {
		t.Fatal("wifi to mobile should reconnect")
	}
	a.mu.Lock()
	a.stopWanted = true
	a.mu.Unlock()
	if a.wantRebind("wlan0") {
		t.Fatal("user disconnect must not reconnect")
	}
	if a.wantRebind("") {
		t.Fatal("empty network")
	}
}

func TestExternalStopBlocksReconnect(t *testing.T) {
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.status = "connected"
	a.lastUnder = "wlan0"
	a.mu.Unlock()
	a.ExternalStop("VPN отключён системой")
	if a.wantRebind("rmnet0") {
		t.Fatal("revoke should not schedule a reconnect")
	}
	a.mu.Lock()
	msg := a.errMsg
	a.mu.Unlock()
	if msg == "" {
		t.Fatal("missing error")
	}
}

func TestWantRebindWhenSameNetworkReturnsAfterLoss(t *testing.T) {
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.status = "connected"
	a.lastUnder = "rmnet0"
	a.mu.Unlock()
	if a.wantRebind("") {
		t.Fatal("loss itself must not reconnect")
	}
	if !a.wantRebind("rmnet0") {
		t.Fatal("same network back after a loss should reconnect")
	}
	if a.wantRebind("rmnet0") {
		t.Fatal("no loss in between: no reconnect")
	}
}
