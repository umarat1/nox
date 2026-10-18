package engine

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"nox/core"
)

// sortByOld keeps the user's manual order across subscription refreshes:
// servers that existed before keep their relative order, new ones go after them in feed order.
func sortByOld(list []core.Server, oldIdx map[string]int) {
	sort.SliceStable(list, func(i, j int) bool {
		a, okA := oldIdx[list[i].Name]
		b, okB := oldIdx[list[j].Name]
		if okA && okB {
			return a < b
		}
		return okA && !okB
	})
}

// ReorderServers puts the given ids, in this order, into the slots those ids occupied
// (so reordering inside a category/subscription never moves servers of other groups).
func (a *App) ReorderServers(ids []string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.p.Servers = reorderSlots(a.p.Servers, ids)
	a.save()
}

func reorderSlots(all []core.Server, ids []string) []core.Server {
	want := map[string]bool{}
	for _, id := range ids {
		want[id] = true
	}
	byID := map[string]core.Server{}
	var slots []int
	for i, s := range all {
		if want[s.ID] {
			slots = append(slots, i)
			byID[s.ID] = s
		}
	}
	k := 0
	out := append([]core.Server(nil), all...)
	for _, id := range ids {
		s, ok := byID[id]
		if !ok || k >= len(slots) {
			continue
		}
		out[slots[k]] = s
		delete(byID, id)
		k++
	}
	return out
}

// ReorderSubs sets the order of subscriptions.
func (a *App) ReorderSubs(ids []string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	pos := map[string]int{}
	for i, id := range ids {
		pos[id] = i
	}
	sort.SliceStable(a.p.Subs, func(i, j int) bool {
		x, ok1 := pos[a.p.Subs[i].ID]
		y, ok2 := pos[a.p.Subs[j].ID]
		if !ok1 {
			x = 1 << 30
		}
		if !ok2 {
			y = 1 << 30
		}
		return x < y
	})
	a.save()
}

// SetGroupOrder persists the order of protocol group headers.
func (a *App) SetGroupOrder(keys []string) {
	a.mu.Lock()
	a.p.GroupOrder = keys
	a.save()
	a.mu.Unlock()
}

// RefreshSub refreshes one subscription.
func (a *App) RefreshSub(id string) string {
	a.mu.Lock()
	var sub *Sub
	for _, s := range a.p.Subs {
		if s.ID == id {
			c := s
			sub = &c
		}
	}
	a.mu.Unlock()
	if sub == nil {
		return "Подписка не найдена"
	}
	if _, _, err := a.fetchSub(sub, false); err != nil {
		return "Ошибка обновления: " + err.Error()
	}
	return "Подписка обновлена"
}

type delEntry struct {
	Idx int
	S   core.Server
}

// DeleteDead removes servers that timed out on the last ping (never Автовыбор).
// The removed ones can be restored with UndoDelete.
func (a *App) DeleteDead(ids []string) int {
	a.mu.Lock()
	defer a.mu.Unlock()
	scope := map[string]bool{}
	for _, id := range ids {
		scope[id] = true
	}
	var del []delEntry
	out := make([]core.Server, 0, len(a.p.Servers))
	for i, s := range a.p.Servers {
		if s.Ping == -1 && s.Type != core.BalancerLabel && (len(ids) == 0 || scope[s.ID]) {
			del = append(del, delEntry{i, s})
			continue
		}
		out = append(out, s)
	}
	if len(del) == 0 {
		return 0
	}
	a.p.Servers = out
	a.lastDeleted = del
	if !a.hasServerLocked(a.p.Selected) && len(out) > 0 {
		a.p.Selected = out[0].ID
	}
	a.save()
	return len(del)
}

func (a *App) UndoDelete() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	n := len(a.lastDeleted)
	for _, d := range a.lastDeleted { // ascending original indices
		i := d.Idx
		if i > len(a.p.Servers) {
			i = len(a.p.Servers)
		}
		a.p.Servers = append(a.p.Servers[:i], append([]core.Server{d.S}, a.p.Servers[i:]...)...)
	}
	a.lastDeleted = nil
	a.save()
	return n
}

func (a *App) ForgetUndo() { a.mu.Lock(); a.lastDeleted = nil; a.mu.Unlock() }

// SubLink returns the subscription URL.
func (a *App) SubLink(id string) string {
	a.mu.Lock()
	defer a.mu.Unlock()
	for _, s := range a.p.Subs {
		if s.ID == id {
			return s.URL
		}
	}
	return ""
}

// ---------------------------------------------------------------- update scheduling (0.7.28)

const (
	updThrottle = 6 * time.Hour
	updRetry    = 2 * time.Minute
	updHide     = 24 * time.Hour
)

var nowFn = time.Now

// updateLoop: check on every launch; skip only if the last *successful* check was <6h ago;
// on failure retry after 2 minutes; keep re-checking every 6h while running.
func (a *App) updateLoop() {
	for {
		a.mu.Lock()
		last := a.p.UpdOK
		a.mu.Unlock()
		wait := time.Duration(0)
		if last > 0 {
			if d := nowFn().Sub(time.Unix(last, 0)); d < updThrottle {
				wait = updThrottle - d
			}
		}
		if wait > 0 {
			time.Sleep(wait)
			continue
		}
		if _, ok := a.checkUpdate(); ok {
			time.Sleep(updThrottle)
		} else {
			time.Sleep(updRetry)
		}
	}
}

// HideUpdate («Позже») hides the given version for 24 h.
func (a *App) HideUpdate(ver string) {
	a.mu.Lock()
	a.p.UpdHideVer = ver
	a.p.UpdHideTill = nowFn().Add(updHide).Unix()
	a.save()
	a.mu.Unlock()
}

func (a *App) visibleUpdLocked() *UpdateInfo {
	u := a.upd
	if u == nil {
		return nil
	}
	if u.Version == a.p.UpdHideVer && nowFn().Unix() < a.p.UpdHideTill {
		return nil
	}
	return u
}

// healthCheck verifies after connecting that traffic really flows through the server
// (sing-box "starts" even if the server is unreachable from this network) and measures
// the real in-tunnel latency for the selected server.
func (a *App) healthCheck(ctx context.Context, srv core.Server, s core.Settings) {
	port := s.ProxyPort
	if port == 0 {
		port = 2080
	}
	pu, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
	cl := &http.Client{Timeout: 8 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(pu)}}
	for try := 0; try < 3; try++ {
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
		t0 := time.Now()
		req, _ := http.NewRequestWithContext(ctx, "GET", "https://www.gstatic.com/generate_204", nil)
		if r, err := cl.Do(req); err == nil {
			r.Body.Close()
			if srv.Type != core.BalancerLabel {
				a.setPing(srv.ID, int(time.Since(t0).Milliseconds()))
			}
			a.mu.Lock()
			if strings.HasPrefix(a.errMsg, "Сервер не отвечает") {
				a.errMsg = ""
			}
			a.mu.Unlock()
			return
		}
	}
	if ctx.Err() != nil {
		return
	}
	a.mu.Lock()
	if a.status == "connected" {
		a.errMsg = "Сервер не отвечает: «" + srv.Name + "» подключён, но трафик не проходит (сервер недоступен из вашей сети или заблокирован). Выберите другой сервер."
	}
	a.mu.Unlock()
	a.log("проверка соединения: нет ответа через " + srv.Name)
}

// BestServer (Android «Автовыбор» on the client side): the fastest server by the last ping,
// skipping balancers and dead ones; tolerance keeps the current one if it is within tolMs.
func (a *App) BestServer(tolMs int) string {
	a.mu.Lock()
	defer a.mu.Unlock()
	var cur *core.Server
	best := -1
	for i, s := range a.p.Servers {
		if s.ID == a.p.Selected {
			cur = &a.p.Servers[i]
		}
		if s.Type == core.BalancerLabel || s.Ping <= 0 {
			continue
		}
		if best < 0 || s.Ping < a.p.Servers[best].Ping {
			best = i
		}
	}
	if best < 0 {
		return ""
	}
	if cur != nil && cur.Ping > 0 && cur.Ping-a.p.Servers[best].Ping <= tolMs {
		return cur.ID
	}
	return a.p.Servers[best].ID
}
