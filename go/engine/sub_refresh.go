package engine

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"nox/core"
)

// subUserAgents: a plain v2rayNG / Happ agent first. Remnawave picks the response
// template by the first matching User-Agent rule. An agent that starts with "Nox/"
// can hit a custom or stale template and keep yesterday's regions; the standard
// clients get the host list the panel has right now. Nox is last, as a fallback.
func subUserAgents() []string {
	return []string{
		"v2rayNG/1.10.16",
		"Happ/2.14.1",
		"v2rayN/7.13.8",
		"sing-box/1.14.3",
		"Nox/" + Version,
	}
}

func deviceOS() string {
	switch runtime.GOOS {
	case "android":
		return "Android"
	case "windows":
		return "Windows"
	case "darwin":
		return "macOS"
	default:
		return "Linux"
	}
}

func (a *App) stampSub(req *http.Request, ua string) {
	req.Header.Set("User-Agent", ua)
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Cache-Control", "no-cache, no-store")
	req.Header.Set("Pragma", "no-cache")
	a.mu.Lock()
	id := a.p.DeviceID
	a.mu.Unlock()
	if id != "" {
		req.Header.Set("x-hwid", id) // Remnawave device id
	}
	req.Header.Set("x-device-os", deviceOS())
	req.Header.Set("x-ver-os", Version)
	req.Header.Set("x-device-model", "Nox")
}

func cacheBust(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	q := u.Query()
	q.Set("nocache", strconv.FormatInt(time.Now().Unix(), 10))
	u.RawQuery = q.Encode()
	return u.String()
}

func headerText(h http.Header, k string) string {
	v := strings.TrimSpace(h.Get(k))
	if strings.HasPrefix(strings.ToLower(v), "base64:") {
		if d, ok := core.B64(v[7:]); ok {
			v = d
		}
	}
	return strings.TrimSpace(v)
}

func isHTMLBody(ct, body string) bool {
	ct = strings.ToLower(ct)
	if strings.Contains(ct, "text/html") {
		return true
	}
	b := strings.ToLower(strings.TrimSpace(body))
	return strings.HasPrefix(b, "<!doctype html") || strings.HasPrefix(b, "<html")
}

func parseIntervalHours(h string) int {
	n, err := strconv.Atoi(strings.TrimSpace(h))
	if err != nil || n <= 0 {
		return 0
	}
	if n > 24*7 {
		n = 24 * 7
	}
	return n
}

type subHit struct {
	servers  []core.Server
	errs     []string
	ua       string
	title    string
	announce string
	web      string
	support  string
	interval int
	info     string
	trusted  bool
}

func (a *App) readSub(cl *http.Client, raw, ua string) (*http.Response, []byte, error) {
	get := func(u string) (*http.Response, []byte, error) {
		req, err := http.NewRequest("GET", u, nil)
		if err != nil {
			return nil, nil, err
		}
		a.stampSub(req, ua)
		resp, err := cl.Do(req)
		if err != nil {
			return nil, nil, err
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
		resp.Body.Close()
		if err != nil {
			return nil, nil, err
		}
		return resp, body, nil
	}
	resp, body, err := get(cacheBust(raw))
	if err != nil {
		return nil, nil, err
	}
	if resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusBadRequest {
		return get(raw)
	}
	return resp, body, nil
}

// fetchSub downloads one subscription and replaces every server that belongs to it.
// Servers of other subscriptions and hand-added servers (empty SubID) are kept.
func (a *App) fetchSub(sub *Sub, isNew bool) (int, []string, error) {
	a.subFetchMu.Lock()
	defer a.subFetchMu.Unlock()
	cl := a.directClient()
	defer cl.CloseIdleConnections()
	var lastErr error
	var fallback *subHit
	var chosen *subHit
	for _, ua := range subUserAgents() {
		resp, body, err := a.readSub(cl, sub.URL, ua)
		if err != nil {
			lastErr = err
			continue
		}
		if resp.StatusCode != 200 {
			lastErr = fmt.Errorf("HTTP %d", resp.StatusCode)
			continue
		}
		text := string(body)
		if isHTMLBody(resp.Header.Get("Content-Type"), text) {
			lastErr = errors.New("панель вернула страницу вместо списка серверов")
			continue
		}
		r := core.ParseContent(text)
		if len(r.Servers) == 0 {
			lastErr = errors.New("серверы не найдены")
			continue
		}
		hit := &subHit{
			servers: r.Servers, errs: r.Errors, ua: ua,
			title: headerText(resp.Header, "profile-title"), announce: headerText(resp.Header, "announce"),
			web: headerText(resp.Header, "profile-web-page-url"), support: headerText(resp.Header, "support-url"),
			interval: parseIntervalHours(resp.Header.Get("profile-update-interval")),
			info:     resp.Header.Get("subscription-userinfo"),
		}
		hit.trusted = hit.info != "" || hit.title != "" || hit.interval > 0
		if hit.trusted {
			chosen = hit
			break // a real subscription response; do not let a later agent append old hosts
		}
		if fallback == nil {
			fallback = hit
		}
	}
	if chosen == nil {
		chosen = fallback
	}
	if chosen == nil {
		if lastErr == nil {
			lastErr = errors.New("серверы не найдены")
		}
		return 0, nil, lastErr
	}
	parseUserInfo(chosen.info, sub)
	if chosen.interval > 0 {
		sub.Interval = chosen.interval
	}
	sub.Announce, sub.WebPage, sub.Support = chosen.announce, chosen.web, chosen.support
	if chosen.title != "" {
		sub.Name = chosen.title
	}
	if sub.Name == "" {
		if u, err := url.Parse(sub.URL); err == nil {
			sub.Name = u.Host
		}
	}
	sub.Updated = time.Now().Unix()
	if descs := a.fetchDescs(sub.URL); descs != nil {
		for i := range chosen.servers {
			if d, ok := descs[chosen.servers[i].Name]; ok && chosen.servers[i].Desc == "" {
				chosen.servers[i].Desc = d
			}
		}
	}
	n := a.applySubServers(sub, chosen.servers, isNew)
	a.log(fmt.Sprintf("подписка %s: список заменён, %d серверов (UA %s)", sub.Name, n, chosen.ua))
	return n, chosen.errs, nil
}

func serverKey(s core.Server) string {
	return s.Name + "|" + s.Type + "|" + strings.ToLower(s.Host) + "|" + strconv.Itoa(s.Port)
}

func sameKeys(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	x, y := append([]string(nil), a...), append([]string(nil), b...)
	sort.Strings(x)
	sort.Strings(y)
	for i := range x {
		if x[i] != y[i] {
			return false
		}
	}
	return true
}

func sameEndpoint(a, b core.Server) bool {
	return a.Type == b.Type && strings.EqualFold(a.Host, b.Host) && a.Port == b.Port
}

// applySubServers drops every server of this subscription and writes the new list.
// Ping and id are kept only when the name and the endpoint are the same, so a renamed
// or moved node is not glued to an old config. The slice is a new array: the old
// backing store is not reused (that alias used to overwrite servers while they were
// still being read).
func (a *App) applySubServers(sub *Sub, servers []core.Server, isNew bool) int {
	a.mu.Lock()
	defer a.mu.Unlock()
	prev := append([]core.Server(nil), a.p.Servers...)
	selName := ""
	oldByName := map[string]core.Server{}
	oldIdx := map[string]int{}
	var keep []core.Server
	for i, s := range prev {
		if s.SubID != sub.ID {
			keep = append(keep, s)
			continue
		}
		if s.ID == a.p.Selected {
			selName = s.Name
		}
		if _, ok := oldByName[s.Name]; !ok {
			oldByName[s.Name] = s
			oldIdx[s.Name] = i
		}
	}
	sortByOld(servers, oldIdx)
	out := append([]core.Server(nil), keep...)
	used := map[string]bool{}
	for _, s := range servers {
		s.SubID = sub.ID
		if o, ok := oldByName[s.Name]; ok && !used[s.Name] && sameEndpoint(o, s) {
			used[s.Name] = true
			s.ID, s.Ping = o.ID, o.Ping
			if s.Desc == "" {
				s.Desc = o.Desc
			}
		} else {
			s.ID = newID()
			if !sameEndpoint(oldByName[s.Name], s) {
				s.Ping = 0
			}
		}
		if s.Name == selName {
			a.p.Selected = s.ID
		}
		out = append(out, s)
	}
	a.p.Servers = out
	found := false
	for i := range a.p.Subs {
		if a.p.Subs[i].ID == sub.ID {
			a.p.Subs[i] = *sub
			found = true
		}
	}
	if !found {
		a.p.Subs = append(a.p.Subs, *sub)
	}
	if isNew {
		a.p.Category = sub.ID
	}
	if a.p.Selected == "" || !a.hasServerLocked(a.p.Selected) {
		a.p.Selected = ""
		for _, s := range a.p.Servers {
			if s.SubID == sub.ID {
				a.p.Selected = s.ID
				break
			}
		}
		if a.p.Selected == "" && len(a.p.Servers) > 0 {
			a.p.Selected = a.p.Servers[0].ID
		}
	}
	a.save()
	return len(servers)
}

func (a *App) RefreshSubs() string {
	a.mu.Lock()
	subs := append([]Sub(nil), a.p.Subs...)
	a.mu.Unlock()
	if len(subs) == 0 {
		return "Нет подписок"
	}
	var fails []string
	for i := range subs {
		if _, _, err := a.fetchSub(&subs[i], false); err != nil {
			name := subs[i].Name
			if name == "" {
				name = "подписка"
			}
			fails = append(fails, name+": "+err.Error())
		}
	}
	if len(fails) > 0 {
		return "Ошибка обновления: " + strings.Join(fails, "; ")
	}
	return "Подписки обновлены"
}

// subLoop refreshes every subscription when the core starts, then again each time
// profile-update-interval (hours) elapses. Missing header → once an hour.
func (a *App) subLoop() {
	time.Sleep(1500 * time.Millisecond)
	a.RefreshSubs()
	a.maybeAutoPing()
	tick := time.NewTicker(time.Minute)
	defer tick.Stop()
	for range tick.C {
		a.refreshDueSubs()
	}
}

func (a *App) refreshDueSubs() {
	a.mu.Lock()
	now := time.Now().Unix()
	var due []Sub
	for _, s := range a.p.Subs {
		hrs := s.Interval
		if hrs <= 0 {
			hrs = 1
		}
		if s.Updated <= 0 || now-s.Updated >= int64(hrs)*3600 {
			due = append(due, s)
		}
	}
	a.mu.Unlock()
	for i := range due {
		if _, _, err := a.fetchSub(&due[i], false); err != nil {
			a.log("автообновление " + due[i].Name + ": " + err.Error())
		}
	}
}

func (a *App) maybeAutoPing() {
	a.mu.Lock()
	on := a.p.Settings.AutoBest
	st := a.status
	n := len(a.p.Servers)
	a.mu.Unlock()
	if on && st == "disconnected" && n > 0 {
		a.PingServers(nil)
	}
}
