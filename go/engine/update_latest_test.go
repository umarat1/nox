package engine

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

// Tests never reach the real sessia.top: LatestURL is blank unless a test serves it.
func TestMain(m *testing.M) {
	LatestURL = ""
	os.Exit(m.Run())
}

// serveLatest serves latest.json at LatestURL and an old-style update.json at UpdateURL.
func serveLatest(t *testing.T, latest, legacy string, latestCode int) {
	mux := http.NewServeMux()
	mux.HandleFunc("/updates/nox/latest.json", func(w http.ResponseWriter, r *http.Request) {
		if latestCode != 200 {
			http.Error(w, `{"error":"not found"}`, latestCode)
			return
		}
		w.Write([]byte(latest))
	})
	mux.HandleFunc("/api/apps/nox/update.json", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(legacy))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	oL, oU, oFB := LatestURL, UpdateURL, UpdateFallbackURLs
	LatestURL, UpdateURL, UpdateFallbackURLs = srv.URL+"/updates/nox/latest.json", srv.URL+"/api/apps/nox/update.json", nil
	updOSTest = "android"
	t.Cleanup(func() { LatestURL, UpdateURL, UpdateFallbackURLs = oL, oU, oFB; updOSTest = "" })
}

func latestJSON(ver string, code int, min string) string {
	return fmt.Sprintf(`{"version":%q,"versionCode":%d,"url":"https://sessia.top/files/Nox-%s-android-arm64-v8a.apk",`+
		`"sha256":"ab12","changelog":"• новое","minSupported":%s}`, ver, code, ver, min)
}

const legacyJSON = `{"versionName":"9.8.7","versionCode":9870,"url":"https://iji.by/dl/legacy.apk","sha256":"cd","notes":"old"}`

func TestLatestJSONPreferred(t *testing.T) {
	serveLatest(t, latestJSON("9.9.0", 9900, "0"), legacyJSON, 200)
	a := newTestApp(t)
	u, ok := a.checkUpdate()
	if !ok || u == nil || u.Version != "9.9.0" || u.Code != 9900 || u.Notes != "• новое" || u.SHA256 != "ab12" || u.Mandatory {
		t.Fatalf("latest.json not used: %+v", u)
	}
}

func TestLatestJSONFallbackWhenMissing(t *testing.T) {
	serveLatest(t, "", legacyJSON, 404)
	u, ok := newTestApp(t).checkUpdate()
	if !ok || u == nil || u.Version != "9.8.7" || u.URL != "https://iji.by/dl/legacy.apk" {
		t.Fatalf("fallback not used: %+v", u)
	}
}

func TestLatestJSONNotNewer(t *testing.T) {
	serveLatest(t, latestJSON(Version, VersionCode, "0"), legacyJSON, 200)
	if u, ok := newTestApp(t).checkUpdate(); !ok || u != nil {
		t.Fatalf("same version offered: %+v", u)
	}
}

func TestLatestJSONMandatory(t *testing.T) {
	for _, min := range []string{fmt.Sprint(VersionCode + 1), fmt.Sprintf(`"%d"`, VersionCode+1), `"99.0"`} {
		serveLatest(t, latestJSON("99.0", 99000, min), legacyJSON, 200)
		a := newTestApp(t)
		a.HideUpdate("99.0") // «Позже» pressed earlier
		u, _ := a.checkUpdate()
		if u == nil || !u.Mandatory {
			t.Fatalf("min %s: not mandatory: %+v", min, u)
		}
		a.HideUpdate("99.0")
		if st := a.GetState().Update; st == nil || !st.Mandatory {
			t.Fatalf("min %s: mandatory update hidden by «Позже»", min)
		}
	}
	for _, min := range []string{fmt.Sprint(VersionCode), `"` + Version + `"`, "null", `""`} {
		serveLatest(t, latestJSON("99.0", 99000, min), legacyJSON, 200)
		if u, _ := newTestApp(t).checkUpdate(); u == nil || u.Mandatory {
			t.Fatalf("min %s: should be optional: %+v", min, u)
		}
	}
}

func TestLatestJSONOffline(t *testing.T) {
	oL, oU, oFB := LatestURL, UpdateURL, UpdateFallbackURLs
	LatestURL, UpdateURL, UpdateFallbackURLs = "http://127.0.0.1:1/latest.json", "http://127.0.0.1:1/u.json", nil
	defer func() { LatestURL, UpdateURL, UpdateFallbackURLs = oL, oU, oFB }()
	if u, ok := newTestApp(t).checkUpdate(); ok || u != nil {
		t.Fatalf("offline must be silent: %v %+v", ok, u)
	}
}

// Windows/macOS need the signed nox2-<os> channel: an unsigned latest.json falls back.
func TestLatestJSONDesktopFallsBack(t *testing.T) {
	serveLatest(t, latestJSON("99.0", 99000, "0"),
		`{"nox2-windows":{"versionName":"99.1","url":"https://x/Nox-Setup-99.1.exe","sha256":"aa","sig":"x"}}`, 200)
	updOSTest = "windows"
	u, ok := newTestApp(t).checkUpdate()
	if !ok || u == nil || u.Version != "99.1" {
		t.Fatalf("windows fallback: %+v", u)
	}
}

// The APK from latest.json is verified against its sha256 before install.
func TestLatestJSONDownloadVerifiesSHA(t *testing.T) {
	apk := []byte("fake apk body")
	sum := sha256.Sum256(apk)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(apk) }))
	defer srv.Close()
	updOSTest = "android"
	defer func() { updOSTest = "" }()
	a := newTestApp(t)
	good := &UpdateInfo{Version: "99.0", URL: srv.URL + "/Nox.apk", SHA256: hex.EncodeToString(sum[:])}
	if _, err := a.download(good); err != nil {
		t.Fatalf("good sha: %v", err)
	}
	bad := &UpdateInfo{Version: "99.0", URL: srv.URL + "/Nox2.apk", SHA256: "00"}
	if _, err := a.download(bad); err == nil {
		t.Fatal("bad sha accepted")
	}
}

func TestLatestMinSupportedSplitCode(t *testing.T) {
	// a server that publishes the arm64 split code (4xxx) is read on the base scale
	for min, want := range map[int]bool{4000 + VersionCode%1000: false, 3000 + VersionCode%1000 + 1: true} {
		if got := belowMin([]byte(fmt.Sprint(min))); got != want {
			t.Fatalf("minSupported %d: mandatory=%v, want %v", min, got, want)
		}
	}
}
