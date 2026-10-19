package engine

import (
	"context"
	"errors"
	"sync"
	"time"
)

// UpdProgress: what the update sheet / notification shows.
// Stage: "download" → "verify" → "install" → "done"; or "error" / "canceled".
type UpdProgress struct {
	Active  bool    `json:"active"`
	Stage   string  `json:"stage"`
	Version string  `json:"version"`
	Done    int64   `json:"done"`
	Total   int64   `json:"total"` // -1 unknown
	Speed   float64 `json:"speed"` // bytes/s, smoothed
	Resumed bool    `json:"resumed"`
	Error   string  `json:"error"`
}

type updJob struct {
	mu     sync.Mutex
	p      UpdProgress
	cancel context.CancelFunc
	lastT  time.Time
	lastB  int64
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
func (a *App) UpdateStart() UpdProgress {
	a.mu.Lock()
	u := a.upd
	a.mu.Unlock()
	updMu.Lock()
	defer updMu.Unlock()
	if updCur != nil && updCur.snap().Active {
		return updCur.snap()
	}
	if u == nil {
		return UpdProgress{Stage: "error", Error: "Обновлений нет"}
	}
	ctx, cancel := context.WithCancel(context.Background())
	j := &updJob{cancel: cancel, p: UpdProgress{Active: true, Stage: "download", Version: u.Version, Total: -1}}
	updCur = j
	go a.runUpdate(ctx, j, u)
	return j.snap()
}

func (a *App) runUpdate(ctx context.Context, j *updJob, u *UpdateInfo) {
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
		return
	}
	j.set(func(p *UpdProgress) { p.Stage, p.Speed = "install", 0 })
	if err := installUpdate(a, path); err != nil {
		j.set(func(p *UpdProgress) { p.Active, p.Stage, p.Error = false, "error", "Установка: "+err.Error() })
		return
	}
	// Android: the system installer is now on screen; Windows: the installer replaces us.
	j.set(func(p *UpdProgress) { p.Active, p.Stage = false, "done" })
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
		j.cancel()
	}
}
