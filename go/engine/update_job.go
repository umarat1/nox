package engine

import (
	"context"
	"errors"
	"os"
	"sync"
	"time"
)

// UpdProgress: what the update sheet / notification shows.
// Stage: "download" → "verify" → "install" → "done"; or "error" / "canceled".
// 2.3.2: a background auto-download stops at "ready" (verified APK on disk, no prompt yet);
// Ready stays true while that file is there, so the UI can offer «Установить X.Y.Z».
type UpdProgress struct {
	Active  bool    `json:"active"`
	Stage   string  `json:"stage"`
	Version string  `json:"version"`
	Done    int64   `json:"done"`
	Total   int64   `json:"total"` // -1 unknown
	Speed   float64 `json:"speed"` // bytes/s, smoothed
	Resumed bool    `json:"resumed"`
	Error   string  `json:"error"`
	Auto    bool    `json:"auto"`  // started by «Автоскачивание обновлений»
	Ready   bool    `json:"ready"` // verified APK downloaded, can be installed now
}

type updJob struct {
	mu     sync.Mutex
	p      UpdProgress
	cancel context.CancelFunc
	lastT  time.Time
	lastB  int64
	// install: run the installer after the download (manual «Обновить», or the user
	// tapped the pill while an auto-download was running).
	install bool
	path    string // verified file once downloaded
	ended   time.Time
}

var (
	updMu  sync.Mutex
	updCur *updJob
)

func (j *updJob) snap() UpdProgress {
	j.mu.Lock()
	defer j.mu.Unlock()
	return j.p
}

func (j *updJob) set(f func(p *UpdProgress)) {
	j.mu.Lock()
	f(&j.p)
	j.mu.Unlock()
}

// UpdateStart begins (or keeps running) the download of the offered update in the
// background; poll UpdateProgress. A partial file from an earlier try is resumed.
// 2.3.2: if an auto-download is running it is switched to "install when done"; if the APK
// is already downloaded and verified ("ready", or a dismissed system prompt) the installer
// opens again straight away.
func (a *App) UpdateStart() UpdProgress {
	if Packaged {
		return UpdProgress{Stage: "error", Error: "Версия MSIX обновляется через Microsoft App Installer: закройте и снова откройте ПРОКСИ+"}
	}
	a.mu.Lock()
	u := a.upd
	a.mu.Unlock()
	updMu.Lock()
	defer updMu.Unlock()
	if j := updCur; j != nil {
		if s := j.snap(); s.Active {
			j.mu.Lock()
			j.install = true
			j.mu.Unlock()
			return j.snap()
		}
		if j.readyFor(u) {
			j.set(func(p *UpdProgress) { p.Active, p.Stage, p.Error, p.Speed = true, "install", "", 0 })
			go a.installJob(j)
			return j.snap()
		}
	}
	if u == nil {
		return UpdProgress{Stage: "error", Error: "Обновлений нет"}
	}
	return a.startJobLocked(u, false).snap()
}

// startJobLocked (updMu held) starts a download job; auto jobs stop at "ready".
func (a *App) startJobLocked(u *UpdateInfo, auto bool) *updJob {
	ctx, cancel := context.WithCancel(context.Background())
	j := &updJob{cancel: cancel, install: !auto, p: UpdProgress{Active: true, Stage: "download", Version: u.Version, Total: -1, Auto: auto}}
	updCur = j
	go a.runUpdate(ctx, j, u)
	return j
}

// readyFor: the job holds a verified file of this version that still exists.
func (j *updJob) readyFor(u *UpdateInfo) bool {
	j.mu.Lock()
	path, v := j.path, j.p.Version
	j.mu.Unlock()
	if path == "" || (u != nil && u.Version != v) {
		return false
	}
	_, err := os.Stat(path)
	return err == nil
}

func (a *App) runUpdate(ctx context.Context, j *updJob, u *UpdateInfo) {
	readyHook := UpdateReadyHook
	first := true
	path, err := a.downloadCtx(ctx, u, func(done, total int64) {
		now := time.Now()
		j.mu.Lock()
		if first {
			j.p.Resumed = done > 0
			j.lastT, j.lastB, first = now, done, false
		}
		if dt := now.Sub(j.lastT).Seconds(); dt >= 0.5 {
			inst := float64(done-j.lastB) / dt
			if j.p.Speed == 0 {
				j.p.Speed = inst
			} else {
				j.p.Speed = j.p.Speed*0.6 + inst*0.4
			}
			j.lastT, j.lastB = now, done
		}
		j.p.Done, j.p.Total = done, total
		if total >= 0 && done >= total {
			j.p.Stage = "verify"
		}
		j.mu.Unlock()
	})
	if err != nil {
		j.set(func(p *UpdProgress) {
			p.Active = false
			if errors.Is(err, context.Canceled) {
				p.Stage, p.Error = "canceled", ""
			} else {
				p.Stage, p.Error = "error", err.Error()
			}
		})
		j.mu.Lock()
		j.ended = time.Now()
		j.mu.Unlock()
		return
	}
	j.mu.Lock()
	j.path = path
	j.p.Ready, j.p.Speed = true, 0
	inst := j.install
	if !inst {
		j.p.Active, j.p.Stage = false, "ready"
		j.ended = time.Now()
	} else {
		j.p.Stage = "install"
	}
	v := j.p.Version
	j.mu.Unlock()
	if !inst {
		a.log("обновление " + v + " скачано и проверено")
		if readyHook != nil {
			go readyHook(v)
		}
		return
	}
	a.installJob(j)
}

// installJob hands the verified file to the system installer (stage "install" set).
func (a *App) installJob(j *updJob) {
	j.mu.Lock()
	path := j.path
	j.mu.Unlock()
	err := installUpdate(a, path)
	j.mu.Lock()
	defer j.mu.Unlock()
	j.ended = time.Now()
	if err != nil {
		j.p.Active, j.p.Stage, j.p.Error = false, "error", "Установка: "+err.Error()
		return
	}
	// Android: the system installer is now on screen; Windows: the installer replaces us.
	j.p.Active, j.p.Stage = false, "done"
}

// UpdateProgress: state of the current/last update job (Stage "" when none ran).
func (a *App) UpdateProgress() UpdProgress {
	updMu.Lock()
	j := updCur
	updMu.Unlock()
	if j == nil {
		return UpdProgress{Total: -1}
	}
	return j.snap()
}

// UpdateCancel stops the download; the partial file is kept for a resume.
func (a *App) UpdateCancel() {
	updMu.Lock()
	j := updCur
	updMu.Unlock()
	if j != nil && j.snap().Stage == "download" {
		updMu.Lock()
		autoSkipVer = j.snap().Version // no background restart of this version until relaunch
		updMu.Unlock()
		j.cancel()
	}
}
