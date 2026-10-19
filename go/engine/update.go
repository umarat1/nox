package engine

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

var UpdateURL = "https://canada2.iji.by/dl/version.json"

// VersionCode is the pubspec build number (108 for 1.0.8). Split APKs use abi*1000+VersionCode;
// update checks compare VersionCode to the server's top-level versionCode (0.7.x style).
const VersionCode = 108

type UpdateInfo struct {
	Version string `json:"versionName"`
	Code    int64  `json:"versionCode"`
	URL     string `json:"url"`
	SHA256  string `json:"sha256"`
	Notes   string `json:"notes"`
	Sig     string `json:"sig"` // base64 ed25519 of lowercase hex SHA-256 (required for nox2-windows)
}

// UpdatePubKey verifies signed installers (private key: signing/nox-update-ed25519.key).
var UpdatePubKey = "1FPIC0CfR+VLt5OXYiUS6GUdhXyWYBRrvS+sGrh/FGA="

// UpdateChannel is the version.json key for the signed Windows/macOS flow.
func UpdateChannel() string { return "nox2-" + osName() }

// AndroidABI: "arm64-v8a" / "armeabi-v7a" / "x86_64" — set by noxcore from Build.SUPPORTED_ABIS[0].
var AndroidABI string

func verifySig(sum, sig string) bool {
	pub, err := base64.StdEncoding.DecodeString(UpdatePubKey)
	s, err2 := base64.StdEncoding.DecodeString(sig)
	return err == nil && err2 == nil && len(pub) == ed25519.PublicKeySize && ed25519.Verify(ed25519.PublicKey(pub), []byte(strings.ToLower(sum)), s)
}

func verLess(a, b string) bool {
	pa, pb := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(pa) || i < len(pb); i++ {
		var x, y int
		if i < len(pa) {
			x, _ = strconv.Atoi(pa[i])
		}
		if i < len(pb) {
			y, _ = strconv.Atoi(pb[i])
		}
		if x != y {
			return x < y
		}
	}
	return false
}

func (a *App) CheckUpdate() *UpdateInfo {
	u, _ := a.checkUpdate()
	if u != nil {
		a.mu.Lock()
		a.p.UpdHideVer = ""
		a.save()
		a.mu.Unlock()
	}
	return u
}

func (a *App) checkUpdate() (*UpdateInfo, bool) {
	cl := a.httpClient()
	cl.Timeout = 15 * time.Second
	resp, err := cl.Get(UpdateURL + "?t=" + strconv.FormatInt(time.Now().Unix(), 10))
	if err != nil {
		return nil, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, false
	}
	var m map[string]json.RawMessage
	if json.NewDecoder(resp.Body).Decode(&m) != nil {
		return nil, false
	}
	a.mu.Lock()
	a.p.UpdOK = nowFn().Unix()
	a.save()
	a.mu.Unlock()

	u, ok := parseUpdate(m)
	if !ok || !updateNewer(u) {
		a.mu.Lock()
		a.upd = nil
		a.mu.Unlock()
		return nil, true
	}
	a.mu.Lock()
	a.upd = u
	a.mu.Unlock()
	a.log("доступно обновление " + u.Version)
	return u, true
}

// parseUpdate prefers the signed nox2-<os> channel; on Android also accepts top-level
// 0.7.x fields (versionCode/url/sha256/notes) and optional per-ABI url_arm64 / url_armv7.
func parseUpdate(m map[string]json.RawMessage) (*UpdateInfo, bool) {
	var u UpdateInfo
	if raw, ok := m[UpdateChannel()]; ok && json.Unmarshal(raw, &u) == nil && u.URL != "" {
		return &u, true
	}
	if osName() != "android" {
		return nil, false
	}
	if json.Unmarshal(flattenTop(m), &u) != nil || u.URL == "" || u.Version == "" {
		return nil, false
	}
	pickAndroidURL(&u, m)
	return &u, true
}

func flattenTop(m map[string]json.RawMessage) json.RawMessage {
	// Rebuild a JSON object from only top-level scalar update fields.
	keep := []string{"versionName", "versionCode", "url", "sha256", "notes", "sig",
		"url_arm64", "url_armv7", "url_armeabi_v7a", "sha256_arm64", "sha256_armv7", "sha256_armeabi_v7a"}
	out := map[string]json.RawMessage{}
	for _, k := range keep {
		if v, ok := m[k]; ok {
			out[k] = v
		}
	}
	b, _ := json.Marshal(out)
	return b
}

func pickAndroidURL(u *UpdateInfo, m map[string]json.RawMessage) {
	abi := AndroidABI
	if abi == "" {
		abi = "arm64-v8a"
	}
	type alt struct{ urlKey, shaKey string }
	var keys alt
	switch {
	case strings.Contains(abi, "arm64"):
		keys = alt{"url_arm64", "sha256_arm64"}
	case strings.Contains(abi, "armeabi") || strings.Contains(abi, "armv7"):
		keys = alt{"url_armv7", "sha256_armv7"}
		if _, ok := m["url_armeabi_v7a"]; ok {
			keys = alt{"url_armeabi_v7a", "sha256_armeabi_v7a"}
		}
	default:
		return // keep universal url
	}
	var url, sha string
	_ = json.Unmarshal(m[keys.urlKey], &url)
	_ = json.Unmarshal(m[keys.shaKey], &sha)
	if url != "" {
		u.URL = url
		if sha != "" {
			u.SHA256 = sha
		}
	}
}

func updateNewer(u *UpdateInfo) bool {
	if u == nil || u.URL == "" {
		return false
	}
	if u.Code > 0 && (runtime.GOOS == "android" || osName() == "android") {
		return u.Code > int64(VersionCode)
	}
	return u.Version != "" && verLess(Version, u.Version)
}

func (a *App) DoUpdate() string {
	a.mu.Lock()
	u := a.upd
	a.mu.Unlock()
	if u == nil {
		return "Обновлений нет"
	}
	if err := applyUpdate(a, u); err != nil {
		return "Ошибка обновления: " + err.Error()
	}
	return ""
}

func (a *App) download(u *UpdateInfo) (string, error) {
	cl := a.httpClient()
	cl.Timeout = 10 * time.Minute
	resp, err := cl.Get(u.URL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	path := filepath.Join(a.dataDir, "update-"+filepath.Base(u.URL))
	f, err := os.Create(path)
	if err != nil {
		return "", err
	}
	h := sha256.New()
	_, err = io.Copy(io.MultiWriter(f, h), resp.Body)
	f.Close()
	if err != nil {
		return "", err
	}
	sum := hex.EncodeToString(h.Sum(nil))
	if u.SHA256 != "" && !strings.EqualFold(sum, u.SHA256) {
		os.Remove(path)
		return "", errors.New("контрольная сумма не совпала")
	}
	// Signed channel (nox2-windows): sig required. Top-level Android APKs (0.7.x style): sha256 only.
	if u.Sig != "" {
		if !verifySig(sum, u.Sig) {
			os.Remove(path)
			return "", errors.New("подпись обновления неверна — установка отменена")
		}
	} else if runtime.GOOS != "android" && osName() != "android" {
		os.Remove(path)
		return "", errors.New("подпись обновления отсутствует — установка отменена")
	} else if u.SHA256 == "" {
		os.Remove(path)
		return "", errors.New("нет sha256 обновления — установка отменена")
	}
	return path, nil
}

func (a *App) CheckUpdateMsg() string {
	u, ok := a.checkUpdate()
	if !ok {
		return "Не удалось проверить обновления"
	}
	if u == nil {
		return "У вас последняя версия"
	}
	a.mu.Lock()
	a.p.UpdHideVer = ""
	a.save()
	a.mu.Unlock()
	return "Доступна версия " + u.Version
}
