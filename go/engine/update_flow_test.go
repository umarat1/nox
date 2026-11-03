package engine

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Live https://iji.by/dl/version.json as published for 1.0.7 (Android part).
const live107 = `{"versionCode":107,"versionName":"1.0.7",
 "url":"https://iji.by/dl/Nox-1.0.7-android-universal.apk","sha256":"cbd9",
 "url_arm64":"https://iji.by/dl/Nox-1.0.7-android-arm64-v8a.apk","sha256_arm64":"729d",
 "url_armv7":"https://iji.by/dl/Nox-1.0.7-android-armeabi-v7a.apk","sha256_armv7":"e6da",
 "nox2-windows":{"versionName":"1.0.7","url":"https://iji.by/dl/Nox-Setup-1.0.7.exe","sha256":"8d88","sig":"x"}}`

// apkCode mirrors android/app/build.gradle.kts: split = abi*1000 + versionCode, universal = versionCode.
func apkCode(url string, code int64) int64 {
	switch {
	case strings.Contains(url, "arm64-v8a"):
		return 2000 + code
	case strings.Contains(url, "armeabi-v7a"):
		return 1000 + code
	}
	return code
}

// Every installed 1.0.6 variant must be offered an APK with a higher versionCode (no downgrade).
func TestAndroidUpdateNeverDowngrades(t *testing.T) {
	var m map[string]json.RawMessage
	if err := json.Unmarshal([]byte(live107), &m); err != nil {
		t.Fatal(err)
	}
	defer func(o string) { AndroidABI = o }(AndroidABI)
	for _, c := range []struct {
		abi       string // ABI of the installed APK's native libs
		installed int64
		wantURL   string
	}{
		{"arm64-v8a", 2106, "arm64-v8a"}, {"armeabi-v7a", 1106, "armeabi-v7a"},
		{"x86_64", 106, "universal"}, {"arm64-v8a", 106, "arm64-v8a"}, // universal on arm64 → split (2107 > 106)
	} {
		AndroidABI = c.abi
		u := &UpdateInfo{}
		json.Unmarshal(flattenTop(m), u)
		pickAndroidURL(u, m)
		if !strings.Contains(u.URL, c.wantURL) || apkCode(u.URL, u.Code) <= c.installed {
			t.Fatalf("%s/%d → %s (vc %d)", c.abi, c.installed, u.URL, apkCode(u.URL, u.Code))
		}
		if u.Code <= 106 { // engine compares the top-level code with its own VersionCode
			t.Fatal("not newer")
		}
	}
}

// The signed desktop channel: real 1.0.9 Windows entry verifies with the production key.
func TestWindowsSignedEntryProduction(t *testing.T) {
	sum := "b093be8f5d3a692dc40a271c0d95be472217f05e3645cf2e6e432e15ad3ee67f"
	sig := "RTdYRLQBERwapHyoKB70SARcv88uuUHdTV2fz7LRoTHBMzkg/YHb+STtVSfcAe5WkaV6NcwP85AkGvBYGXgECA=="
	if !verifySig(sum, sig) || !verifySig(strings.ToUpper(sum), sig) {
		t.Fatal("production signature does not verify")
	}
	if verifySig(strings.Replace(sum, "b0", "b1", 1), sig) {
		t.Fatal("tampered sum verified")
	}
}

// download(): signed channel accepted only with matching sha256 + signature; unsigned refused off Android.
func TestDesktopDownloadRequiresSignature(t *testing.T) {
	body := []byte("MZ fake installer")
	h := sha256.Sum256(body)
	sum := hex.EncodeToString(h[:])
	pub, priv, _ := ed25519.GenerateKey(nil)
	defer func(o string) { UpdatePubKey = o }(UpdatePubKey)
	UpdatePubKey = base64.StdEncoding.EncodeToString(pub)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(body) }))
	defer srv.Close()
	a := pairApp(t)
	good := base64.StdEncoding.EncodeToString(ed25519.Sign(priv, []byte(sum)))
	other := base64.StdEncoding.EncodeToString(ed25519.Sign(priv, []byte("00"+sum[2:])))
	if p, err := a.download(&UpdateInfo{URL: srv.URL + "/Nox-Setup-9.exe", SHA256: sum, Sig: good}); err != nil || p == "" {
		t.Fatal("valid signed update refused:", err)
	}
	if _, err := a.download(&UpdateInfo{URL: srv.URL + "/x.exe", SHA256: sum, Sig: other}); err == nil {
		t.Fatal("bad signature accepted")
	}
	if _, err := a.download(&UpdateInfo{URL: srv.URL + "/x.exe", SHA256: "00" + sum[2:], Sig: good}); err == nil {
		t.Fatal("bad sha accepted")
	}
	if _, err := a.download(&UpdateInfo{URL: srv.URL + "/x.exe", SHA256: sum}); err == nil {
		t.Fatal("unsigned desktop update accepted")
	}
	// parseUpdate takes the signed channel entry for this OS and ignores top-level fields
	m := map[string]json.RawMessage{}
	json.Unmarshal([]byte(live107), &m)
	m[UpdateChannel()] = m["nox2-windows"]
	u, ok := parseUpdate(m)
	if !ok || !strings.HasSuffix(u.URL, ".exe") || u.Sig == "" || !updateNewer(u) == verLess(Version, "1.0.7") {
		t.Fatalf("%+v", u)
	}
}
