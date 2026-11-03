package engine

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"nox/core"
)

// autoEnv: Android update paths with a local APK server; slow trickles the body.
func autoEnv(t *testing.T, slow *atomic.Bool) (*App, *atomic.Int32, *atomic.Value, *atomic.Value) {
	t.Helper()
	body := bytes.Repeat([]byte("nox-apk-"), 128<<10) // 1 MB
	h := sha256.Sum256(body)
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		if slow != nil && slow.Load() && r.Header.Get("Range") == "" {
			w.Header().Set("Content-Length", "1048576")
			for i := 0; i < len(body); i += 32 << 10 {
				if _, err := w.Write(body[i : i+32<<10]); err != nil {
					return
				}
				w.(http.Flusher).Flush()
				time.Sleep(20 * time.Millisecond)
			}
			return
		}
		http.ServeContent(w, r, "x.apk", time.Time{}, bytes.NewReader(body))
	}))
	t.Cleanup(srv.Close)
	var installed, ready atomic.Value
	installHook = func(p string) error { installed.Store(p); return nil }
	UpdateReadyHook = func(v string) { ready.Store(v) }
	updOSTest = "android"
	o := NetMetered
	t.Cleanup(func() {
		installHook, UpdateReadyHook, updOSTest, NetMetered = nil, nil, "", o
		updMu.Lock()
		updCur, autoSkipVer = nil, ""
		updMu.Unlock()
	})
	updMu.Lock()
	updCur, autoSkipVer = nil, ""
	updMu.Unlock()
	a := pairApp(t)
	a.upd = &UpdateInfo{Version: "2.3.3", URL: srv.URL + "/ProxyPlus-2.3.3.apk", SHA256: hex.EncodeToString(h[:])}
	return a, &hits, &installed, &ready
}

func setAutoDl(a *App, m string) {
	a.mu.Lock()
	a.p.Settings.AutoDl = m
	a.mu.Unlock()
}

// Default (empty = upgrading user, or "always"): background download stops at "ready"
// with no installer; the ready hook fires; UpdateStart then installs the same file.
func TestAutoDownloadReadyThenInstall(t *testing.T) {
	a, hits, installed, ready := autoEnv(t, nil)
	if core.DefaultSettings().AutoDl != "always" || AutoDlMode("") != "always" {
		t.Fatal("default must be «Всегда»")
	}
	if !a.maybeAutoDownload() {
		t.Fatal("auto-download did not start")
	}
	p := waitStage(t, a, "ready", "error")
	if p.Stage != "ready" || !p.Ready || !p.Auto || p.Active {
		t.Fatalf("ready: %+v", p)
	}
	if installed.Load() != nil {
		t.Fatal("auto-download must not open the installer by itself")
	}
	for i := 0; i < 100 && ready.Load() == nil; i++ {
		time.Sleep(10 * time.Millisecond)
	}
	if ready.Load() != "2.3.3" {
		t.Fatalf("ready hook: %v", ready.Load())
	}
	if st := a.GetState(); st.UpdJob == nil || !st.UpdJob.Ready || st.UpdJob.Stage != "ready" {
		t.Fatalf("GetState.updJob: %+v", st.UpdJob)
	}
	if a.maybeAutoDownload() {
		t.Fatal("ready file must not be downloaded again")
	}
	n := hits.Load()
	if p := a.UpdateStart(); p.Stage != "install" || !p.Active {
		t.Fatalf("install start: %+v", p)
	}
	waitStage(t, a, "done")
	if installed.Load() == nil || hits.Load() != n {
		t.Fatalf("install from the ready file: %v hits %d→%d", installed.Load(), n, hits.Load())
	}
	// dismissed system prompt: the pill's «Установить» opens it again from the same file
	installed.Store("")
	if p := a.UpdateStart(); p.Stage != "install" {
		t.Fatalf("re-open: %+v", p)
	}
	waitStage(t, a, "done")
	if installed.Load() == "" || hits.Load() != n {
		t.Fatal("re-open must reuse the verified file")
	}
}

// «Только Wi‑Fi»: only on an unmetered network; «Выкл»: never; desktop: never.
func TestAutoDownloadModes(t *testing.T) {
	a, _, _, _ := autoEnv(t, nil)
	setAutoDl(a, "off")
	if a.maybeAutoDownload() {
		t.Fatal("off started a download")
	}
	setAutoDl(a, "wifi")
	NetMetered = nil
	if a.maybeAutoDownload() {
		t.Fatal("wifi-only with unknown network started")
	}
	NetMetered = func() int { return 1 }
	if a.maybeAutoDownload() {
		t.Fatal("wifi-only on mobile data started")
	}
	NetMetered = func() int { return 0 }
	if !a.maybeAutoDownload() {
		t.Fatal("wifi-only on Wi‑Fi did not start")
	}
	waitStage(t, a, "ready")
	updOSTest = "windows"
	updMu.Lock()
	updCur = nil
	updMu.Unlock()
	setAutoDl(a, "always")
	if a.maybeAutoDownload() {
		t.Fatal("desktop must stay manual")
	}
	// hidden («Позже») versions are not fetched
	updOSTest = "android"
	a.HideUpdate("2.3.3")
	if a.maybeAutoDownload() {
		t.Fatal("hidden update downloaded")
	}
}

// Tapping the pill while the background download runs installs right after it.
func TestAutoDownloadTapDuringDownload(t *testing.T) {
	var slow atomic.Bool
	slow.Store(true)
	a, _, installed, _ := autoEnv(t, &slow)
	a.maybeAutoDownload()
	if p := a.UpdateStart(); !p.Active || p.Stage != "download" {
		t.Fatalf("attach: %+v", p)
	}
	waitStage(t, a, "done", "error")
	if installed.Load() == nil {
		t.Fatal("installer not opened after the attached download")
	}
}

// Wi‑Fi only and the phone moves to mobile data: the download pauses (partial kept) and
// resumes with a Range request back on Wi‑Fi. A user cancel stops background retries.
func TestAutoDownloadPauseResumeCancel(t *testing.T) {
	var slow atomic.Bool
	slow.Store(true)
	a, _, _, _ := autoEnv(t, &slow)
	setAutoDl(a, "wifi")
	var metered atomic.Int32
	NetMetered = func() int { return int(metered.Load()) }
	a.maybeAutoDownload()
	for i := 0; i < 200 && a.UpdateProgress().Done < 128<<10; i++ {
		time.Sleep(10 * time.Millisecond)
	}
	metered.Store(1)
	a.maybeAutoDownload()
	if p := waitStage(t, a, "canceled"); p.Done == 0 {
		t.Fatalf("pause: %+v", p)
	}
	slow.Store(false)
	metered.Store(0)
	if !a.maybeAutoDownload() {
		t.Fatal("no resume on Wi‑Fi")
	}
	if p := waitStage(t, a, "ready"); !p.Resumed {
		t.Fatalf("not resumed: %+v", p)
	}
	// user cancel → no background restart of that version until the setting changes
	updMu.Lock()
	updCur = nil
	updMu.Unlock()
	os.Remove(filepath.Join(a.dataDir, "update-ProxyPlus-2.3.3.apk"))
	slow.Store(true)
	a.maybeAutoDownload()
	a.UpdateCancel()
	waitStage(t, a, "canceled")
	if a.maybeAutoDownload() {
		t.Fatal("restarted after a user cancel")
	}
	a.SaveSettings(func() core.Settings { s := a.p.Settings; s.AutoDl = "always"; return s }())
	for i := 0; i < 100 && a.UpdateProgress().Stage == "canceled"; i++ {
		time.Sleep(10 * time.Millisecond)
	}
	if s := a.UpdateProgress().Stage; s != "download" && s != "verify" && s != "ready" {
		t.Fatalf("setting change did not restart: %s", s)
	}
	waitStage(t, a, "ready")
}

// A verified file from before a restart is reused without a request; no update → cleanup.
func TestAutoDownloadReuseAndCleanup(t *testing.T) {
	a, hits, _, _ := autoEnv(t, nil)
	a.maybeAutoDownload()
	waitStage(t, a, "ready")
	n := hits.Load()
	updMu.Lock()
	updCur = nil // process restart
	updMu.Unlock()
	a.maybeAutoDownload()
	waitStage(t, a, "ready")
	if hits.Load() != n {
		t.Fatal("verified file was downloaded again")
	}
	a.cleanupUpdateFiles()
	if m, _ := filepath.Glob(filepath.Join(a.dataDir, "update-*")); len(m) != 0 {
		t.Fatalf("left: %v", m)
	}
}
