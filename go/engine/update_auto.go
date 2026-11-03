package engine

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

// 2.3.2 «Автоскачивание обновлений» (Android): when an update is offered, the APK for this
// ABI is downloaded in the background (resumable, sha256-verified) and the job stops at
// "ready". The UI then opens the system installer once per version per launch and shows
// «Установить X.Y.Z» on the pill; the host posts a «готово к установке» notification.
//
// Settings.AutoDl: "always" (default, also when empty) | "wifi" (unmetered networks only) | "off".

var (
	// NetMetered (Android host): 1 = metered (mobile data), 0 = unmetered (Wi-Fi/Ethernet),
	// -1 = unknown / no network.
	NetMetered func() int
	// UpdateReadyHook (Android host): a verified update APK is ready to install.
	UpdateReadyHook func(version string)

	autoSkipVer string             // user cancelled this version's download (updMu)
	autoRetry   = 10 * time.Minute // after a failed background download
)

// AutoDlMode normalises the setting.
func AutoDlMode(s string) string {
	switch s {
	case "wifi", "off":
		return s
	}
	return "always"
}

// autoDlNetOK: may the background download use the current network?
func autoDlNetOK(mode string) bool {
	switch mode {
	case "off":
		return false
	case "wifi":
		return NetMetered != nil && NetMetered() == 0
	}
	return true
}

// maybeAutoDownload starts the background download of the offered (not hidden) update
// when the setting and the network allow it. Cheap; called after update checks, on
// Resume and from the 1-minute update ticker.
func (a *App) maybeAutoDownload() bool {
	if updOS() != "android" {
		return false // desktop installers replace the running app: keep them manual
	}
	a.mu.Lock()
	u := a.visibleUpdLocked()
	mode := AutoDlMode(a.p.Settings.AutoDl)
	a.mu.Unlock()
	netOK := autoDlNetOK(mode)
	updMu.Lock()
	defer updMu.Unlock()
	if j := updCur; j != nil && !netOK {
		// «Выкл» chosen, or Wi‑Fi only and now on mobile data: pause a background
		// download (the partial file is kept and resumed later). A manual one goes on.
		j.mu.Lock()
		bg := j.p.Active && j.p.Auto && !j.install && j.p.Stage == "download"
		j.mu.Unlock()
		if bg {
			j.cancel()
		}
	}
	if u == nil || u.URL == "" || !netOK {
		return false
	}
	if autoSkipVer == u.Version {
		return false
	}
	if j := updCur; j != nil {
		s := j.snap()
		if s.Active || (s.Version == u.Version && j.readyFor(u)) {
			return false
		}
		j.mu.Lock()
		ended := j.ended
		j.mu.Unlock()
		if s.Version == u.Version && s.Stage == "error" && time.Since(ended) < autoRetry {
			return false
		}
	}
	a.log("автоскачивание обновления " + u.Version)
	a.startJobLocked(u, true)
	return true
}

// cleanupUpdateFiles removes downloaded APKs once no update is offered (installed or withdrawn).
func (a *App) cleanupUpdateFiles() {
	updMu.Lock()
	busy := updCur != nil && updCur.snap().Active
	updMu.Unlock()
	if busy || updOS() != "android" {
		return
	}
	m, _ := filepath.Glob(filepath.Join(a.dataDir, "update-*"))
	for _, f := range m {
		if strings.HasSuffix(f, ".apk") || strings.HasSuffix(f, ".part") || strings.HasSuffix(f, ".src") {
			os.Remove(f)
		}
	}
}

// updJobState: the job for GetState, nil when none ran.
func updJobState() *UpdProgress {
	updMu.Lock()
	j := updCur
	updMu.Unlock()
	if j == nil {
		return nil
	}
	s := j.snap()
	if s.Ready && !j.readyFor(nil) {
		s.Ready = false
	}
	return &s
}
