package engine

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// Subscription auto-refresh: the 1-minute timer (and Resume) re-fetches a subscription
// once its profile-update-interval (hours) has passed, adopts the interval from the
// header, and backs off 5 min after a failed fetch.
func TestSubAutoRefreshTimer(t *testing.T) {
	var hits int32
	fail := int32(0)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&hits, 1)
		if atomic.LoadInt32(&fail) == 1 {
			http.Error(w, "down", 502)
			return
		}
		w.Header().Set("profile-update-interval", "2")
		w.Write([]byte(subNew))
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	now := time.Now().Unix()
	a.mu.Lock()
	a.p.Subs = []Sub{{ID: "s1", URL: srv.URL, Name: "Серверная", Updated: now - 600}} // 10 min ago, default 1h
	a.mu.Unlock()
	a.refreshDueSubs()
	if hits != 0 {
		t.Fatal("not due yet")
	}
	a.mu.Lock()
	a.p.Subs[0].Updated = now - 3700
	a.mu.Unlock()
	a.refreshDueSubs()
	a.mu.Lock()
	s := a.p.Subs[0]
	a.mu.Unlock()
	if hits == 0 || s.Interval != 2 || s.Updated < now {
		t.Fatalf("due after 1h: hits=%d %+v", hits, s)
	}
	// header said 2h: 1h later it is not due
	a.mu.Lock()
	a.p.Subs[0].Updated = now - 3700
	a.mu.Unlock()
	h := atomic.LoadInt32(&hits)
	a.refreshDueSubs()
	if atomic.LoadInt32(&hits) != h {
		t.Fatal("interval 2h ignored")
	}
	// failure: retried after 5 min, not every minute
	atomic.StoreInt32(&fail, 1)
	a.mu.Lock()
	a.p.Subs[0].Updated = now - 3*3600
	a.mu.Unlock()
	a.refreshDueSubs()
	h = atomic.LoadInt32(&hits)
	a.refreshDueSubs()
	if atomic.LoadInt32(&hits) != h {
		t.Fatal("hammering after failure")
	}
	// Resume (app back in front) refreshes due subscriptions too
	atomic.StoreInt32(&fail, 0)
	a.mu.Lock()
	a.subFail = nil
	a.mu.Unlock()
	a.Resume()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		a.mu.Lock()
		u := a.p.Subs[0].Updated
		a.mu.Unlock()
		if u >= now {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("Resume did not refresh the due subscription")
}
