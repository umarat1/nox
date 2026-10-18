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
	"strconv"
	"strings"
	"time"
)

var UpdateURL = "https://canada2.iji.by/dl/version.json"

type UpdateInfo struct {
	Version string `json:"versionName"`
	URL     string `json:"url"`
	SHA256  string `json:"sha256"`
	Notes   string `json:"notes"`
	Sig     string `json:"sig"` // base64 ed25519 signature of the lowercase hex SHA-256
}

// UpdatePubKey verifies installers (private key: signing/nox-update-ed25519.key, never shipped).
var UpdatePubKey = "1FPIC0CfR+VLt5OXYiUS6GUdhXyWYBRrvS+sGrh/FGA="

// UpdateChannel is the version.json key; separate from 0.8.x ("windows") so old clients are untouched.
func UpdateChannel() string { return "nox2-" + osName() }

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

// CheckUpdate is the manual «Проверить обновления»: always queries the server and clears «Позже».
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

// checkUpdate reads version.json -> "windows"/"macos" entry. ok=false on network/parse failure.
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
	var u UpdateInfo
	if raw, ok := m[UpdateChannel()]; !ok || json.Unmarshal(raw, &u) != nil || u.URL == "" || !verLess(Version, u.Version) {
		a.mu.Lock()
		a.upd = nil
		a.mu.Unlock()
		return nil, true
	}
	a.mu.Lock()
	a.upd = &u
	a.mu.Unlock()
	a.log("доступно обновление " + u.Version)
	return &u, true
}

// DoUpdate downloads the installer (Windows: verifies SHA-256 and runs it) or opens the DMG link (macOS).
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
	path := filepath.Join(a.dataDir, "update-"+filepath.Base(u.URL)) // ProgramData (not user-writable %TEMP%) for the service
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
	if !verifySig(sum, u.Sig) {
		os.Remove(path)
		return "", errors.New("подпись обновления неверна — установка отменена")
	}
	return path, nil
}

// CheckUpdateMsg backs the «Проверить обновления» button and distinguishes network errors.
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
