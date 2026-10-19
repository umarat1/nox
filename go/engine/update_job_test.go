package engine

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func waitStage(t *testing.T, a *App, want ...string) UpdProgress {
	t.Helper()
	for i := 0; i < 300; i++ {
		p := a.UpdateProgress()
		for _, w := range want {
			if p.Stage == w {
				return p
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("stage %v not reached: %+v", want, a.UpdateProgress())
	return UpdProgress{}
}

// Progress, cancel, Range resume, verify, install hook, bad sha → error + clean restart.
func TestUpdateJobProgressCancelResume(t *testing.T) {
	body := bytes.Repeat([]byte("nox-apk-"), 256<<10) // 2 MB
	h := sha256.Sum256(body)
	sum := hex.EncodeToString(h[:])
	pub, priv, _ := ed25519.GenerateKey(nil)
	defer func(o string) { UpdatePubKey = o }(UpdatePubKey)
	UpdatePubKey = base64.StdEncoding.EncodeToString(pub)
	sig := base64.StdEncoding.EncodeToString(ed25519.Sign(priv, []byte(sum)))
	var slow atomic.Bool
	var ranges atomic.Int32
	slow.Store(true)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Range") != "" {
			ranges.Add(1)
		}
		if slow.Load() { // trickle so the test can cancel mid-way
			w.Header().Set("Content-Length", "2097152")
			for i := 0; i < len(body); i += 64 << 10 {
				if _, err := w.Write(body[i : i+64<<10]); err != nil {
					return
				}
				w.(http.Flusher).Flush()
				time.Sleep(15 * time.Millisecond)
			}
			return
		}
		http.ServeContent(w, r, "x.apk", time.Time{}, bytes.NewReader(body))
	}))
	defer srv.Close()
	var installed atomic.Value
	installHook = func(p string) error { installed.Store(p); return nil }
	defer func() { installHook = nil }()

	a := pairApp(t)
	a.upd = &UpdateInfo{Version: "9.9.9", URL: srv.URL + "/Nox-9.apk", SHA256: sum, Sig: sig}
	if p := a.UpdateStart(); !p.Active || p.Stage != "download" || p.Version != "9.9.9" {
		t.Fatalf("start: %+v", p)
	}
	// wait for some bytes, then cancel
	for i := 0; i < 200 && a.UpdateProgress().Done < 512<<10; i++ {
		time.Sleep(10 * time.Millisecond)
	}
	p := a.UpdateProgress()
	if p.Total != int64(len(body)) || p.Done == 0 {
		t.Fatalf("progress: %+v", p)
	}
	a.UpdateCancel()
	p = waitStage(t, a, "canceled")
	if p.Active || p.Error != "" {
		t.Fatalf("cancel: %+v", p)
	}
	if fi, err := os.Stat(a.dataDir + "/update-Nox-9.apk.part"); err != nil || fi.Size() == 0 {
		t.Fatal("partial file not kept", err)
	}
	// retry resumes with Range and completes
	slow.Store(false)
	a.UpdateStart()
	p = waitStage(t, a, "done", "error")
	if p.Stage != "done" || !p.Resumed || ranges.Load() == 0 || p.Done != int64(len(body)) {
		t.Fatalf("resume: %+v ranges=%d", p, ranges.Load())
	}
	if ip, _ := installed.Load().(string); !strings.HasSuffix(ip, "update-Nox-9.apk") {
		t.Fatal("install hook path", ip)
	}
	if b, _ := os.ReadFile(a.dataDir + "/update-Nox-9.apk"); !bytes.Equal(b, body) {
		t.Fatal("resumed file differs")
	}
	// wrong sha: error stage, partial dropped so the next try starts clean
	a.upd = &UpdateInfo{Version: "9.9.10", URL: srv.URL + "/Nox-10.apk", SHA256: "00" + sum[2:], Sig: sig}
	a.UpdateStart()
	p = waitStage(t, a, "error", "done")
	if p.Stage != "error" || !strings.Contains(p.Error, "контрольная сумма") {
		t.Fatalf("bad sha: %+v", p)
	}
	if _, err := os.Stat(a.dataDir + "/update-Nox-10.apk.part"); err == nil {
		t.Fatal("bad partial kept")
	}
}
