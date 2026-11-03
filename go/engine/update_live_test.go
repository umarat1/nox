package engine

import (
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// testdata/update-2.1.4-live.json is sessia.top's update.json as published for 2.1.4.
// Bump it to the next patch the way the release script does and check that every
// platform build is offered it.
func nextUpdateJSON(t *testing.T) (string, string) {
	b, err := os.ReadFile("testdata/update-2.1.4-live.json")
	if err != nil {
		t.Fatal(err)
	}
	p := strings.Split(Version, ".")
	next := p[0] + "." + p[1] + ".99"
	body := regexp.MustCompile(`"versionName":\s*"[^"]*"`).ReplaceAllString(string(b), `"versionName": "`+next+`"`)
	body = regexp.MustCompile(`"versionCode":\s*\d+`).ReplaceAllString(body, `"versionCode": 3999`)
	return body, next
}

func serveUpdate(t *testing.T, body string, hits *int32) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits != nil {
			atomic.AddInt32(hits, 1)
		}
		w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	old, oldFB := UpdateURL, UpdateFallbackURLs
	UpdateURL, UpdateFallbackURLs = srv.URL, nil
	t.Cleanup(func() { UpdateURL, UpdateFallbackURLs = old, oldFB })
}

func TestLiveUpdateJSONOffersNext(t *testing.T) {
	body, next := nextUpdateJSON(t)
	serveUpdate(t, body, nil)
	defer func() { updOSTest = ""; AndroidABI = "" }()
	for _, c := range []struct{ os, abi, url string }{
		{"android", "arm64-v8a", "arm64-v8a.apk"},
		{"android", "armeabi-v7a", "armeabi-v7a.apk"},
		{"windows", "", "Nox-Setup-"},
		{"macos", "", "macos.dmg"},
	} {
		updOSTest, AndroidABI = c.os, c.abi
		a := newTestApp(t)
		u, ok := a.checkUpdate()
		if !ok || u == nil || u.Version != next || !strings.Contains(u.URL, c.url) || a.GetState().Update == nil {
			t.Fatalf("%s/%s: %s not offered: %+v", c.os, c.abi, next, u)
		}
	}
	// same version is not offered
	updOSTest = "android"
	b, _ := os.ReadFile("testdata/update-2.1.4-live.json")
	same := regexp.MustCompile(`"versionName":\s*"[^"]*"`).ReplaceAllString(string(b), `"versionName": "`+Version+`"`)
	serveUpdate(t, same, nil)
	if u, ok := newTestApp(t).checkUpdate(); !ok || u != nil {
		t.Fatalf("same version offered: %+v", u)
	}
}

// 2.1.5: launch always checks, even right after a successful check (the old loop slept
// out the 6h throttle first and its sleep stalls while a phone sleeps).
func TestUpdateCheckedOnLaunchDespiteThrottle(t *testing.T) {
	body, next := nextUpdateJSON(t)
	var hits int32
	serveUpdate(t, body, &hits)
	updOSTest = "android"
	defer func() { updOSTest = "" }()
	defer func(o time.Duration) { updFirst = o }(updFirst)
	updFirst = 10 * time.Millisecond
	a := newTestApp(t)
	a.mu.Lock()
	a.p.UpdOK = time.Now().Add(-time.Minute).Unix() // checked a minute ago in the previous run
	a.mu.Unlock()
	go a.updateLoop()
	deadline := time.Now().Add(3 * time.Second)
	for a.GetState().Update == nil && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if st := a.GetState().Update; st == nil || st.Version != next || atomic.LoadInt32(&hits) != 1 {
		t.Fatalf("launch check: hits=%d upd=%+v", hits, st)
	}
}

// The periodic re-check is wall-clock based: due 6h after the last success, 2 min after a failure.
func TestUpdateDueWallClock(t *testing.T) {
	a := newTestApp(t)
	now := time.Now()
	defer func() { nowFn = time.Now }()
	nowFn = func() time.Time { return now }
	a.p.UpdOK = now.Add(-5 * time.Hour).Unix()
	if a.updDue() {
		t.Fatal("5h: not due")
	}
	a.p.UpdOK = now.Add(-6*time.Hour - time.Second).Unix()
	if !a.updDue() {
		t.Fatal("6h: due")
	}
	a.updFail = now.Add(-time.Minute).Unix()
	if a.updDue() {
		t.Fatal("failed 1 min ago: wait")
	}
	a.updFail = now.Add(-3 * time.Minute).Unix()
	if !a.updDue() {
		t.Fatal("failed 3 min ago: retry")
	}
	// Resume() runs the same check
	body, _ := nextUpdateJSON(t)
	var hits int32
	serveUpdate(t, body, &hits)
	updOSTest = "android"
	defer func() { updOSTest = "" }()
	a.Resume()
	deadline := time.Now().Add(3 * time.Second)
	for atomic.LoadInt32(&hits) == 0 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if atomic.LoadInt32(&hits) == 0 {
		t.Fatal("Resume did not check")
	}
}

// VersionCode must follow pubspec's build number.
func TestVersionCodeMatchesPubspec(t *testing.T) {
	b, err := os.ReadFile("../../app/pubspec.yaml")
	if err != nil {
		t.Skip(err)
	}
	m := regexp.MustCompile(`(?m)^version:\s*([\d.]+)\+(\d+)`).FindStringSubmatch(string(b))
	if m == nil || m[1] != Version || m[2] != strconv.Itoa(VersionCode) {
		t.Fatalf("pubspec %v vs engine %s+%d", m, Version, VersionCode)
	}
}
