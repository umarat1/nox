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

// subUserAgent is the only User-Agent on subscription requests.
// The panel keeps NOX-only protocols when the agent contains NOX/<version>
// (it matches the word "nox", or the older VPS/<digit> token). Happ and v2rayNG
// agents are classified as Happ and those protocols are stripped, so they are
// never sent — not even as a fallback.
func subUserAgent() string {
	return "NOX/" + Version + " " + deviceOS()
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

func (a *App) stampSub(req *http.Request) {
	req.Header.Set("User-Agent", subUserAgent())
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
	nextURL  string
}

func (a *App) readSub(cl *http.Client, raw string) (*http.Response, []byte, error) {
	get := func(u string) (*http.Response, []byte, error) {
		req, err := http.NewRequest("GET", u, nil)
		if err != nil {
			return nil, nil, err
		}
		a.stampSub(req)
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
	cl := a.subClient()
	defer cl.CloseIdleConnections()
	ua := subUserAgent()
	var chosen *subHit
	var lastErr error
	resp, body, err := a.readSub(cl, sub.URL)
	if err != nil {
		lastErr = err
	} else if resp.StatusCode != 200 {
		lastErr = fmt.Errorf("HTTP %d", resp.StatusCode)
	} else {
		text := string(body)
		if isHTMLBody(resp.Header.Get("Content-Type"), text) {
			lastErr = errors.New("панель вернула страницу вместо списка серверов")
		} else {
			r := core.ParseContent(text)
			if len(r.Servers) == 0 {
				lastErr = errors.New("серверы не найдены")
			} else {
				chosen = &subHit{
					servers: r.Servers, errs: r.Errors, ua: ua,
					title: headerText(resp.Header, "profile-title"), announce: headerText(resp.Header, "announce"),
					web: headerText(resp.Header, "profile-web-page-url"), support: headerText(resp.Header, "support-url"),
					interval: parseIntervalHours(resp.Header.Get("profile-update-interval")),
					info:     resp.Header.Get("subscription-userinfo"),
					nextURL:  nextSubURL(resp.Header),
				}
			}
		}
	}
	if chosen == nil {
		if lastErr == nil {
			lastErr = errors.New("серверы не найдены")
		}
		a.log("подписка " + sub.Name + ": " + lastErr.Error())
		return 0, nil, friendlyNetErr(lastErr)
	}
	if chosen.nextURL != "" && chosen.nextURL != sub.URL {
		a.log("подписка " + sub.Name + ": следующий адрес " + chosen.nextURL)
		sub.URL = chosen.nextURL
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
	n := a.applySubServers(sub, chosen.servers, isNew)
	a.log(fmt.Sprintf("подписка %s: список заменён, %d серверов (UA %s)", sub.Name, n, chosen.ua))
	// Descriptions are a second panel request. The list is already saved; don't hold the
	// refresh button on that round trip (it used to add another full timeout while VPN DNS hung).
	go a.fillDescs(sub.ID, sub.URL)
	return n, chosen.errs, nil
}

func (a *App) fillDescs(subID, raw string) {
	defer func() { _ = recover() }()
	descs := a.fetchDescs(raw)
	if len(descs) == 0 {
		return
	}
	a.mu.Lock()
	changed := false
	for i := range a.p.Servers {
		s := &a.p.Servers[i]
		if s.SubID != subID || s.Desc != "" {
			continue
		}
		if d, ok := descs[s.Name]; ok && d != "" {
			s.Desc = d
			changed = true
		}
	}
	if changed {
		a.save()
	}
	a.mu.Unlock()
}

// nextSubURL is the panel telling the client where the subscription moved.
// profile-update-url is the usual header; update-url is accepted as well.
func nextSubURL(h http.Header) string {
	for _, k := range []string{"profile-update-url", "update-url"} {
		raw := strings.TrimSpace(headerText(h, k))
		if raw == "" {
			continue
		}
		u, err := url.Parse(raw)
		if err != nil || u.Host == "" || (u.Scheme != "https" && u.Scheme != "http") {
			continue
		}
		return u.String()
	}
	return ""
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
	go a.pingFresh("")
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
