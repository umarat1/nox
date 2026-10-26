package engine

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"nox/core"
	"nox/noxproto"
)

// Path memory: which server type last worked on this network. NOX carrier
// memory lives in noxproto; this layer remembers the protocol (NOX, VLESS, …)
// so auto-switch can prefer one that already passed on the current network.
type pathFile struct {
	Nets map[string]pathRec `json:"nets"`
}

type pathRec struct {
	Type string `json:"type"`
	OK   bool   `json:"ok"`
	Unix int64  `json:"unix"`
}

var pathMu sync.Mutex

func (a *App) markPath(typ string, ok bool) {
	if a == nil || a.dataDir == "" || typ == "" || typ == core.BalancerLabel {
		return
	}
	key := noxproto.NetworkLabel()
	pathMu.Lock()
	defer pathMu.Unlock()
	f := loadPath(a.pathFile())
	rec := f.Nets[key]
	rec.Unix = time.Now().Unix()
	if ok {
		rec.Type = typ
		rec.OK = true
	} else if rec.Type == typ || rec.Type == "" {
		rec.Type = typ
		rec.OK = false
	}
	f.Nets[key] = rec
	b, err := json.Marshal(f)
	if err != nil {
		return
	}
	tmp := a.pathFile() + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		_ = os.Rename(tmp, a.pathFile())
	}
}

func (a *App) preferredType() string {
	if a == nil || a.dataDir == "" {
		return ""
	}
	pathMu.Lock()
	defer pathMu.Unlock()
	f := loadPath(a.pathFile())
	rec := f.Nets[noxproto.NetworkLabel()]
	if !rec.OK {
		return ""
	}
	return rec.Type
}

func (a *App) pathFile() string { return filepath.Join(a.dataDir, "path-memory.json") }

func loadPath(path string) pathFile {
	f := pathFile{Nets: map[string]pathRec{}}
	b, err := os.ReadFile(path)
	if err != nil {
		return f
	}
	_ = json.Unmarshal(b, &f)
	if f.Nets == nil {
		f.Nets = map[string]pathRec{}
	}
	return f
}

// fallbackTransport runs when a NOX server cannot be dialed and auto-switch is on.
// Carriers inside NOX are already rotated by the dialer; this step moves to a
// different server (often a different protocol) and remembers the failure.
func (a *App) fallbackTransport(ctx context.Context, srv core.Server, s core.Settings, depth int, tried map[string]bool, cause error) (error, bool) {
	if srv.Type != "NOX" || !s.AutoSwitch || depth >= 2 || ctx.Err() != nil {
		return nil, false
	}
	a.markPath(srv.Type, false)
	a.mu.Lock()
	var list []core.Server
	for _, cand := range a.p.Servers {
		if !tried[cand.ID] {
			list = append(list, cand)
		}
	}
	next := a.pickNext(list, srv)
	a.mu.Unlock()
	if next == nil || tried[next.ID] {
		return nil, false
	}
	a.log(fmt.Sprintf("NOX: путь не открылся (%s), пробую «%s»", cause.Error(), strings.TrimSpace(next.Name)))
	a.mu.Lock()
	prev := a.p.Selected
	a.p.Selected = next.ID
	a.save()
	a.mu.Unlock()
	err := a.connectTry(ctx, *next, s, depth+1, tried)
	if err != nil {
		a.mu.Lock()
		a.p.Selected = prev
		a.save()
		a.mu.Unlock()
	}
	return err, true
}

// pickNext prefers a protocol that already worked on this network, then the
// usual "other protocol, same country" order.
func (a *App) pickNext(all []core.Server, cur core.Server) *core.Server {
	pref := a.preferredType()
	if pref != "" && pref != cur.Type {
		for i := range all {
			s := all[i]
			if s.ID == cur.ID || s.Type != pref || s.Ping == -1 {
				continue
			}
			if s.Type == core.BalancerLabel || s.Type == "qWDTT" || core.IsFullTunnel(s.Outbound) {
				continue
			}
			cp := s
			return &cp
		}
	}
	return nextServer(all, cur)
}
