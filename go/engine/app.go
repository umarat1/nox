package engine

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"nox/core"
)

const Version = "1.0.4"

type Sub struct {
	ID       string `json:"id"`
	URL      string `json:"url"`
	Name     string `json:"name"`
	Updated  int64  `json:"updated"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
	Total    int64  `json:"total"`
	Expire   int64  `json:"expire"`
	Announce string `json:"announce,omitempty"`
	WebPage  string `json:"webPage,omitempty"`
	Support  string `json:"support,omitempty"`
}

type Persist struct {
	Subs      []Sub         `json:"subs"`
	Servers   []core.Server `json:"servers"`
	Selected  string        `json:"selected"`
	Settings  core.Settings `json:"settings"`
	HintsSeen bool          `json:"hintsSeen"`
	DeviceID  string        `json:"deviceId"`
	Category  string        `json:"category"`
	Sort      string        `json:"sort"`
	SetVer    int           `json:"setVer"`
	// 0.7.28 update check state
	UpdOK       int64  `json:"updOk"`       // unix time of last successful check
	UpdHideVer  string `json:"updHideVer"`  // version hidden by «Позже»
	UpdHideTill int64  `json:"updHideTill"` // until when
	// 0.7.29 order of protocol groups (by type label)
	GroupOrder []string `json:"groupOrder"`
}

type App struct {
	// Service: running as the Windows service (LocalSystem). System proxy and per-user
	// autostart are then applied by the UI process in the user's session, not here.
	Service bool
	mu      sync.Mutex
	p       Persist
	dataDir string
	binDir  string

	status   string // disconnected|connecting|connected|disconnecting
	errMsg   string
	pinging  bool
	pingDone int
	pingAll  int
	since    int64

	box     coreProc
	qw      *exec.Cmd
	xr      *xrayProc // Xray-core for an XHTTP server
	captcha *CaptchaReq
	qwStdin io.WriteCloser
	tun     *exec.Cmd // sstpc (Linux)
	sstpUp  bool      // Windows RAS SSTP entry dialed
	cancel  context.CancelFunc
	logBuf  []string

	up, down, upTotal, downTotal int64
	hist                         [][2]int64
	histSeq                      int64 // samples ever taken this session (UI uses it to scroll the graph smoothly)
	clashAddr                    string
	proxySet                     bool
	upd                          *UpdateInfo
	lastDeleted                  []delEntry
	notice                       string // informational banner (auto-switch)
	migrated                     bool   // first run: settings were taken from the old VPS app
	physHint                     uint32 // physical NIC index remembered before the tunnel came up
	lastSwitch                   time.Time
}

// NewApp: dataDir holds state.json (service: %ProgramData%\Nox); binDir holds sing-box, qwdtt,
// and rule-sets. Empty values = per-user defaults (desktop/dev mode).
func NewApp(dataDir, binDir string) *App {
	a := &App{status: "disconnected"}
	if binDir == "" {
		exe, _ := os.Executable()
		binDir = filepath.Dir(exe)
	}
	a.binDir = binDir
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base, _ = os.UserConfigDir()
	}
	if dataDir == "" {
		dataDir = filepath.Join(base, "Nox")
	}
	a.dataDir = dataDir
	os.MkdirAll(a.dataDir, 0o700)
	if _, err := os.Stat(filepath.Join(a.dataDir, "state.json")); err != nil { // first run: take subscriptions from VPS
		if b, err := os.ReadFile(filepath.Join(base, "VPS", "state.json")); err == nil {
			os.WriteFile(filepath.Join(a.dataDir, "state.json"), b, 0o600)
			a.migrated = true
		}
	}
	a.p.Settings = core.DefaultSettings()
	if b, err := os.ReadFile(filepath.Join(a.dataDir, "state.json")); err == nil {
		json.Unmarshal(b, &a.p)
	}
	a.p.Servers = dropOpenVPN(a.p.Servers)
	if a.p.SetVer < 25 { // 0.7.25: Russian sites bypass on by default (as on Android)
		a.p.Settings.DirectRU = true
		a.p.SetVer = 25
		a.save()
	}
	if a.p.DeviceID == "" {
		b := make([]byte, 8)
		rand.Read(b)
		a.p.DeviceID = hex.EncodeToString(b)
		a.save()
	}
	return a
}

func (a *App) bin(n string) string { return binPath(a.binDir, n) }

// ImportLegacy takes a state.json of Nox 0.8 / VPS (read by the UI from the user's
// %LOCALAPPDATA%) when the service has no subscriptions yet. Returns true if imported.
func (a *App) ImportLegacy(stateJSON string) bool {
	var p Persist
	dropped := 0
	if ap, n, ok := convertAndroidLegacy([]byte(stateJSON)); ok {
		p, dropped = ap, n
		if len(p.Servers) == 0 && len(p.Subs) == 0 {
			return false
		}
	} else if json.Unmarshal([]byte(stateJSON), &p) != nil || len(p.Servers) == 0 {
		return false
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if len(a.p.Servers) > 0 || len(a.p.Subs) > 0 {
		return false
	}
	dev := a.p.DeviceID
	p.Servers = dropOpenVPN(p.Servers)
	a.p = p
	if a.p.DeviceID == "" {
		a.p.DeviceID = dev
	}
	if a.p.Settings.Mode == "" {
		a.p.Settings = core.DefaultSettings()
	}
	a.save()
	a.logLocked(fmt.Sprintf("перенесено из старой версии: %d подписок, %d серверов", len(p.Subs), len(p.Servers)))
	if dropped > 0 {
		a.logLocked(fmt.Sprintf("не перенесено %d серверов (xray/mihomo/OpenFlux/OpenVPN нет в Nox 1.0)", dropped))
	}
	return true
}

// Start runs background loops (update check, auto-connect). Call once.
func (a *App) Start() {
	go a.updateLoop()
	if a.migrated && a.p.Settings.Autostart && !a.Service {
		// old VPS autostart task -> Nox task (setAutostart also removes the legacy "VPS" task)
		go func() {
			if err := setAutostart(true); err != nil {
				a.log("автозапуск: " + err.Error())
			}
		}()
	}
	if a.p.Settings.AutoConn && a.p.Selected != "" {
		go func() { time.Sleep(800 * time.Millisecond); a.Connect() }()
	}
}

// Shutdown stops the tunnel and engines.
func (a *App) Shutdown() { a.stopAll() }

func (a *App) save() {
	b, _ := json.MarshalIndent(a.p, "", " ")
	tmp := filepath.Join(a.dataDir, "state.json.tmp")
	if os.WriteFile(tmp, b, 0o600) == nil {
		os.Rename(tmp, filepath.Join(a.dataDir, "state.json"))
	}
}

func (a *App) log(s string) {
	a.mu.Lock()
	a.logLocked(s)
	a.mu.Unlock()
}
func (a *App) logLocked(s string) {
	a.logBuf = append(a.logBuf, time.Now().Format("15:04:05 ")+s)
	if len(a.logBuf) > 400 {
		a.logBuf = a.logBuf[len(a.logBuf)-400:]
	}
}

func newID() string { b := make([]byte, 6); rand.Read(b); return hex.EncodeToString(b) }

// ---------------------------------------------------------------- state for UI

type UIState struct {
	Version    string        `json:"version"`
	Subs       []Sub         `json:"subs"`
	Servers    []core.Server `json:"servers"`
	Selected   string        `json:"selected"`
	Settings   core.Settings `json:"settings"`
	HintsSeen  bool          `json:"hintsSeen"`
	Status     string        `json:"status"`
	Error      string        `json:"error"`
	Pinging    bool          `json:"pinging"`
	PingDone   int           `json:"pingDone"`
	PingAll    int           `json:"pingAll"`
	Since      int64         `json:"since"`
	Category   string        `json:"category"`
	Sort       string        `json:"sort"`
	Core       string        `json:"core"`
	Update     *UpdateInfo   `json:"update"`
	OS         string        `json:"os"`
	GroupOrder []string      `json:"groupOrder"`
	CanUndo    int           `json:"canUndo"`
	Notice     string        `json:"notice"`
	Captcha    *CaptchaReq   `json:"captcha"`
}

func (a *App) GetState() UIState {
	a.mu.Lock()
	defer a.mu.Unlock()
	return UIState{Version, a.p.Subs, a.p.Servers, a.p.Selected, a.p.Settings, a.p.HintsSeen, a.status, a.errMsg,
		a.pinging, a.pingDone, a.pingAll, a.since, a.p.Category, a.p.Sort, coreLabel(), a.visibleUpdLocked(), osName(), a.p.GroupOrder, len(a.lastDeleted), a.notice, a.captcha}
}

type Traffic struct {
	Up, Down, UpTotal, DownTotal int64
	Hist                         [][2]int64
	Seq                          int64
}

func (a *App) GetTraffic() Traffic {
	a.mu.Lock()
	defer a.mu.Unlock()
	h := make([][2]int64, len(a.hist))
	copy(h, a.hist)
	return Traffic{a.up, a.down, a.upTotal, a.downTotal, h, a.histSeq}
}

func (a *App) GetLog() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return strings.Join(a.logBuf, "\n")
}

func (a *App) SetHintsSeen()        { a.mu.Lock(); a.p.HintsSeen = true; a.save(); a.mu.Unlock() }
func (a *App) SetCategory(c string) { a.mu.Lock(); a.p.Category = c; a.save(); a.mu.Unlock() }
func (a *App) SetSort(c string)     { a.mu.Lock(); a.p.Sort = c; a.save(); a.mu.Unlock() }
func (a *App) ClearError()          { a.mu.Lock(); a.errMsg = ""; a.notice = ""; a.mu.Unlock() }
func (a *App) Select(id string) {
	a.mu.Lock()
	changed := a.p.Selected != id
	a.p.Selected = id
	a.save()
	st := a.status
	a.mu.Unlock()
	if changed && (st == "connected" || st == "connecting") {
		go func() { a.Disconnect(); a.Connect() }()
	}
}

func (a *App) SaveSettings(s core.Settings) string {
	a.mu.Lock()
	old := a.p.Settings
	a.p.Settings = s
	a.save()
	a.mu.Unlock()
	if old.Autostart != s.Autostart && !a.Service {
		if err := setAutostart(s.Autostart); err != nil {
			return "Автозапуск: " + err.Error()
		}
	}
	return ""
}

func (a *App) DeleteServer(id string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	out := a.p.Servers[:0]
	for _, s := range a.p.Servers {
		if s.ID != id {
			out = append(out, s)
		}
	}
	a.p.Servers = out
	a.save()
}

func (a *App) DeleteSub(id string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	out := a.p.Servers[:0]
	for _, s := range a.p.Servers {
		if s.SubID != id {
			out = append(out, s)
		}
	}
	a.p.Servers = out
	subs := a.p.Subs[:0]
	for _, s := range a.p.Subs {
		if s.ID != id {
			subs = append(subs, s)
		}
	}
	a.p.Subs = subs
	if a.p.Category == id {
		a.p.Category = ""
	}
	a.save()
}

func (a *App) ServerLink(id string) string {
	a.mu.Lock()
	defer a.mu.Unlock()
	for _, s := range a.p.Servers {
		if s.ID == id {
			return string(s.Outbound)
		}
	}
	return ""
}

// ---------------------------------------------------------------- import

type ImportResult struct {
	Added  int      `json:"added"`
	Errors []string `json:"errors"`
	Msg    string   `json:"msg"`
}

func looksLikeSubURL(t string) bool {
	l := strings.ToLower(t)
	if !(strings.HasPrefix(l, "http://") || strings.HasPrefix(l, "https://")) {
		if strings.Contains(t, "://") || strings.ContainsAny(t, " \n") || !strings.Contains(t, ".") || !strings.Contains(t, "/") {
			return false
		}
	}
	return !strings.ContainsAny(strings.TrimSpace(t), " \n")
}

func (a *App) Import(text string) ImportResult {
	t := strings.TrimSpace(text)
	if t == "" {
		return ImportResult{Msg: "Буфер обмена пуст"}
	}
	if looksLikeSubURL(t) {
		u := t
		if !strings.Contains(strings.ToLower(u), "://") {
			u = "https://" + u
		}
		sub := Sub{ID: newID(), URL: u}
		n, errs, err := a.fetchSub(&sub, true)
		if err != nil {
			return ImportResult{Msg: "Не удалось загрузить подписку: " + err.Error()}
		}
		return ImportResult{Added: n, Errors: errs, Msg: fmt.Sprintf("Добавлено серверов: %d", n)}
	}
	r := core.ParseContent(t)
	if len(r.Servers) == 0 {
		return ImportResult{Errors: r.Errors, Msg: "Ничего не найдено для импорта"}
	}
	a.mu.Lock()
	for i := range r.Servers {
		r.Servers[i].ID = newID()
		a.p.Servers = append(a.p.Servers, r.Servers[i])
	}
	if a.p.Selected == "" {
		a.p.Selected = r.Servers[0].ID
	}
	a.save()
	a.mu.Unlock()
	return ImportResult{Added: len(r.Servers), Errors: r.Errors, Msg: fmt.Sprintf("Добавлено серверов: %d", len(r.Servers))}
}

var userAgents = []string{"v2rayNG/1.10.16 Nox/" + Version, "Happ/2.7.0 Nox/" + Version, "v2rayN/7.13.8", "sing-box 1.14.2"}

func parseUserInfo(h string, s *Sub) {
	for _, part := range strings.Split(h, ";") {
		k, v, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok {
			continue
		}
		f, _ := strconv.ParseFloat(strings.TrimSpace(v), 64)
		switch strings.ToLower(k) {
		case "upload":
			s.Upload = int64(f)
		case "download":
			s.Download = int64(f)
		case "total":
			s.Total = int64(f)
		case "expire":
			s.Expire = int64(f)
		}
	}
}

func (a *App) httpClient() *http.Client {
	tr := &http.Transport{Proxy: nil, TLSHandshakeTimeout: 15 * time.Second}
	a.mu.Lock()
	if a.status == "connected" && a.p.Settings.Mode == "proxy" {
		pu, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", a.p.Settings.ProxyPort))
		tr.Proxy = http.ProxyURL(pu)
	}
	a.mu.Unlock()
	return &http.Client{Timeout: 25 * time.Second, Transport: tr}
}

func (a *App) fetchSub(sub *Sub, isNew bool) (int, []string, error) {
	cl := a.httpClient()
	var lastErr error
	for _, ua := range userAgents {
		req, _ := http.NewRequest("GET", sub.URL, nil)
		req.Header.Set("User-Agent", ua)
		req.Header.Set("Accept", "*/*")
		resp, err := cl.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
		resp.Body.Close()
		if resp.StatusCode != 200 {
			lastErr = fmt.Errorf("HTTP %d", resp.StatusCode)
			continue
		}
		r := core.ParseContent(string(body))
		if len(r.Servers) == 0 {
			lastErr = errors.New("серверы не найдены")
			continue
		}
		parseUserInfo(resp.Header.Get("subscription-userinfo"), sub)
		hdr := func(k string) string {
			v := strings.TrimSpace(resp.Header.Get(k))
			if strings.HasPrefix(v, "base64:") {
				if d, ok := core.B64(v[7:]); ok {
					v = d
				}
			}
			return v
		}
		sub.Announce, sub.WebPage, sub.Support = hdr("announce"), hdr("profile-web-page-url"), hdr("support-url")
		if t := resp.Header.Get("profile-title"); t != "" {
			if strings.HasPrefix(t, "base64:") {
				if d, ok := core.B64(t[7:]); ok {
					t = d
				}
			}
			sub.Name = strings.TrimSpace(t)
		}
		if sub.Name == "" {
			if u, err := url.Parse(sub.URL); err == nil {
				sub.Name = u.Host
			}
		}
		sub.Updated = time.Now().Unix()
		descs := a.fetchDescs(sub.URL)
		for i := range r.Servers {
			if d, ok := descs[r.Servers[i].Name]; ok && r.Servers[i].Desc == "" {
				r.Servers[i].Desc = d
			}
		}
		a.mu.Lock()
		// keep selection by name when refreshing
		selName := ""
		for _, s := range a.p.Servers {
			if s.ID == a.p.Selected && s.SubID == sub.ID {
				selName = s.Name
			}
		}
		old := map[string]core.Server{}
		keep := a.p.Servers[:0]
		for _, s := range a.p.Servers {
			if s.SubID == sub.ID {
				old[s.Name] = s
			} else {
				keep = append(keep, s)
			}
		}
		oldIdx := map[string]int{}
		for i, s := range a.p.Servers {
			if s.SubID == sub.ID {
				oldIdx[s.Name] = i
			}
		}
		a.p.Servers = keep
		sortByOld(r.Servers, oldIdx)
		for _, s := range r.Servers {
			s.SubID = sub.ID
			if o, ok := old[s.Name]; ok {
				s.ID, s.Ping = o.ID, o.Ping
				if s.Desc == "" {
					s.Desc = o.Desc
				}
			} else {
				s.ID = newID()
			}
			if s.Name == selName {
				a.p.Selected = s.ID
			}
			a.p.Servers = append(a.p.Servers, s)
		}
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
			a.p.Selected = r.Servers[0].ID
			for _, s := range a.p.Servers {
				if s.SubID == sub.ID {
					a.p.Selected = s.ID
					break
				}
			}
		}
		a.save()
		a.mu.Unlock()
		a.log(fmt.Sprintf("подписка %s: %d серверов (UA %s)", sub.Name, len(r.Servers), ua))
		return len(r.Servers), r.Errors, nil
	}
	return 0, nil, lastErr
}

// fetchDescs: Remnawave sends host serverDescription only to "extended" clients (Happ UA).
func (a *App) fetchDescs(u string) map[string]string {
	req, _ := http.NewRequest("GET", u, nil)
	req.Header.Set("User-Agent", "Happ/3.0.0 VPS/"+Version)
	cl := a.httpClient()
	cl.Timeout = 10 * time.Second
	resp, err := cl.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil
	}
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
	return core.DescMap(string(b))
}

func (a *App) hasServerLocked(id string) bool {
	for _, s := range a.p.Servers {
		if s.ID == id {
			return true
		}
	}
	return false
}

func (a *App) RefreshSubs() string {
	a.mu.Lock()
	subs := append([]Sub(nil), a.p.Subs...)
	a.mu.Unlock()
	var fails []string
	for i := range subs {
		if _, _, err := a.fetchSub(&subs[i], false); err != nil {
			fails = append(fails, subs[i].Name+": "+err.Error())
		}
	}
	if len(fails) > 0 {
		return "Ошибка обновления: " + strings.Join(fails, "; ")
	}
	return "Подписки обновлены"
}

// ---------------------------------------------------------------- ping

func (a *App) PingServers(ids []string) {
	a.mu.Lock()
	if a.pinging {
		a.mu.Unlock()
		return
	}
	var list []core.Server
	want := map[string]bool{}
	for _, id := range ids {
		want[id] = true
	}
	for _, s := range a.p.Servers {
		if len(ids) == 0 || want[s.ID] {
			list = append(list, s)
		}
	}
	a.pinging, a.pingDone, a.pingAll = true, 0, len(list)
	mode := a.p.Settings.PingMode
	a.mu.Unlock()
	go func() {
		defer func() { a.mu.Lock(); a.pinging = false; a.mu.Unlock() }()
		res := a.ping(list, mode)
		a.mu.Lock()
		for i := range a.p.Servers {
			if v, ok := res[a.p.Servers[i].ID]; ok {
				a.p.Servers[i].Ping = v
			}
		}
		a.save()
		a.mu.Unlock()
	}()
}

func (a *App) setPing(id string, v int) {
	a.mu.Lock()
	for i := range a.p.Servers {
		if a.p.Servers[i].ID == id {
			a.p.Servers[i].Ping = v
		}
	}
	a.pingDone++
	a.mu.Unlock()
}

func freePort() int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 29090
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func (a *App) ping(list []core.Server, mode string) map[string]int {
	res := map[string]int{}
	var mu sync.Mutex
	set := func(id string, v int) { mu.Lock(); res[id] = v; mu.Unlock(); a.setPing(id, v) }
	atomic.StoreInt32(&boundDNSDead, 0)
	pn := a.pingNetwork() // VPN on: sockets pinned to the physical NIC, bypassing the tunnel
	var wg sync.WaitGroup
	var urlList []core.Server
	sem := make(chan struct{}, 16)
	var bals []core.Server
	for _, s := range list {
		s := s
		if s.Type == core.BalancerLabel {
			bals = append(bals, s)
			continue
		}
		if core.IsFullTunnel(s.Outbound) {
			wg.Add(1)
			go func() {
				defer wg.Done()
				if strings.HasSuffix(s.Type, "UDP") {
					set(s.ID, -2)
					return
				}
				set(s.ID, pn.tcpPing(s.Host, s.Port))
			}()
			continue
		}
		if s.Type == "qWDTT" {
			wg.Add(1)
			go func() { defer wg.Done(); set(s.ID, a.qwdttPing(s)) }()
			continue
		}
		if mode == "tcp" {
			wg.Add(1)
			go func() {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()
				if isUDPType(s.Type) {
					set(s.ID, -2)
					return
				}
				set(s.ID, pn.tcpPing(s.Host, s.Port))
			}()
			continue
		}
		urlList = append(urlList, s)
	}
	if len(urlList) > 0 {
		a.urlTest(urlList, set, pn)
	}
	wg.Wait()
	for _, b := range bals {
		best := -1
		a.mu.Lock()
		names := map[string]bool{}
		for _, n := range b.Members {
			names[n] = true
		}
		for _, x := range a.p.Servers {
			if x.SubID == b.SubID && names[x.Name] && x.Ping > 0 && (best < 0 || x.Ping < best) {
				best = x.Ping
			}
		}
		a.mu.Unlock()
		set(b.ID, best)
	}
	return res
}

func isUDPType(t string) bool {
	t = strings.ToLower(t)
	return strings.HasPrefix(t, "hysteria") || t == "tuic" || t == "wireguard"
}

func (a *App) urlTest(list []core.Server, set func(string, int), pn pingNet) {
	port := freePort()
	ctrl := fmt.Sprintf("127.0.0.1:%d", port)
	var outs, eps []any
	tags := map[string]string{}
	// XHTTP servers: one Xray instance, one loopback SOCKS port each, tested through sing-box
	var xobs []json.RawMessage
	var xidx []int
	for i, s := range list {
		if core.IsXray(s.Outbound) {
			xobs, xidx = append(xobs, s.Outbound), append(xidx, i)
		}
	}
	xport := map[int]int{}
	if len(xobs) > 0 {
		x, err := a.startXray("ping", xobs, pn)
		if err != nil {
			a.log("пинг XHTTP: " + err.Error())
			for _, i := range xidx {
				set(list[i].ID, -1)
			}
		} else {
			defer x.Stop()
			for k, i := range xidx {
				xport[i] = x.ports[k]
			}
		}
	}
	for i, s := range list {
		var ob map[string]any
		if core.IsXray(s.Outbound) {
			p, ok := xport[i]
			if !ok {
				continue
			}
			ob = socksOut(p)
		} else if json.Unmarshal(s.Outbound, &ob) != nil {
			set(s.ID, -1)
			continue
		}
		tag := "s" + strconv.Itoa(i)
		ob["tag"] = tag
		pinIP(ob, pn)
		tags[tag] = s.ID
		if ob["type"] == "wireguard" {
			eps = append(eps, ob)
		} else {
			outs = append(outs, ob)
		}
	}
	outs = append(outs, map[string]any{"type": "direct", "tag": "direct"})
	route := map[string]any{"final": "direct", "default_domain_resolver": "local", "auto_detect_interface": true}
	dns := map[string]any{"servers": []any{map[string]any{"type": "local", "tag": "local"}}}
	if pn.bound && pn.nic.Name != "" {
		// VPN is up: a second sing-box would auto-detect the VPN adapter as "default", so pin
		// the test instance to the physical NIC explicitly; DNS goes to a public resolver over it.
		route = map[string]any{"final": "direct", "default_domain_resolver": "pub", "default_interface": pn.nic.Name}
		dns = map[string]any{"servers": []any{map[string]any{"type": "udp", "tag": "pub", "server": "77.88.8.8"},
			map[string]any{"type": "local", "tag": "local"}}}
	}
	cfg := map[string]any{"log": map[string]any{"level": "error"}, "outbounds": outs, "endpoints": eps,
		"dns": dns, "route": route,
		"experimental": map[string]any{"clash_api": map[string]any{"external_controller": ctrl}}}
	b, _ := json.Marshal(cfg)
	path := filepath.Join(a.dataDir, "urltest.json")
	os.WriteFile(path, b, 0o600)
	var out syncBuf
	cmd, err := startTestCore(a, path, &out)
	if err != nil {
		for _, id := range tags {
			set(id, -1)
		}
		a.log("пинг: не удалось запустить sing-box: " + err.Error())
		return
	}
	defer func() { cmd.Stop(); os.Remove(path) }()
	cl := &http.Client{Timeout: 4 * time.Second, Transport: &http.Transport{Proxy: nil}}
	up := false
	for i := 0; i < 100; i++ {
		if r, err := cl.Get("http://" + ctrl + "/version"); err == nil {
			r.Body.Close()
			up = true
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if !up {
		a.log("пинг: sing-box не запустился: " + lastLines(out.String(), 5))
		for _, id := range tags {
			set(id, -1)
		}
		return
	}
	checkURLs := []string{"https://www.gstatic.com/generate_204", "https://cp.cloudflare.com/generate_204"}
	a.mu.Lock()
	if u := strings.TrimSpace(a.p.Settings.PingURL); strings.HasPrefix(u, "http") {
		checkURLs = []string{u, checkURLs[0]}
	}
	a.mu.Unlock()
	var wg sync.WaitGroup
	sem := make(chan struct{}, 16)
	for tag, id := range tags {
		tag, id := tag, id
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			// 2.5 s budget, one retry on the second check point
			for _, u := range checkURLs {
				r, err := cl.Get("http://" + ctrl + "/proxies/" + tag + "/delay?timeout=2500&url=" + url.QueryEscape(u))
				if err != nil {
					continue
				}
				var d struct{ Delay int }
				json.NewDecoder(r.Body).Decode(&d)
				r.Body.Close()
				if d.Delay > 0 {
					set(id, d.Delay)
					return
				}
			}
			set(id, -1)
		}()
	}
	wg.Wait()
}

func lastLines(s string, n int) string {
	ls := strings.Split(strings.TrimSpace(s), "\n")
	if len(ls) > n {
		ls = ls[len(ls)-n:]
	}
	return strings.Join(ls, " | ")
}

func dnsAnswers(server string) bool {
	c, err := net.DialTimeout("udp", server+":53", 1500*time.Millisecond)
	if err != nil {
		return false
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(1500 * time.Millisecond))
	n, _ := rand.Int(rand.Reader, big.NewInt(0xFFFF))
	id := n.Int64()
	q := []byte{byte(id >> 8), byte(id), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 6}
	q = append(q, "api.vk"...)
	q = append(q, 2)
	q = append(q, "me"...)
	q = append(q, 0, 0, 1, 0, 1)
	c.Write(q)
	buf := make([]byte, 512)
	m, err := c.Read(buf)
	return err == nil && m > 12 && buf[0] == q[0] && buf[1] == q[1]
}

func pickDNS(q core.Qwdtt) string {
	if q.GoDNS != "" {
		return q.GoDNS
	}
	if dnsAnswers("77.88.8.8") {
		return "yandex"
	}
	if dnsAnswers("8.8.8.8") {
		return "google"
	}
	return "doh-google"
}

func (a *App) qwdttPing(s core.Server) int {
	q, err := core.QwdttFromOutbound(s.Outbound)
	if err != nil {
		return -1
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, a.bin("qwdtt"), q.PingArgs(pickDNS(q))...)
	cmd.Dir = a.dataDir
	hideWindow(cmd)
	out, _ := cmd.CombinedOutput()
	for _, l := range strings.Split(string(out), "\n") {
		if i := strings.Index(l, "PING_RESULT|"); i >= 0 {
			if v, err := strconv.Atoi(strings.TrimSpace(l[i+12:])); err == nil && v > 0 {
				return v
			}
		}
	}
	return -1
}

// ---------------------------------------------------------------- connect

func (a *App) Connect() {
	a.mu.Lock()
	if a.status != "disconnected" {
		a.mu.Unlock()
		return
	}
	var srv *core.Server
	for i := range a.p.Servers {
		if a.p.Servers[i].ID == a.p.Selected {
			s := a.p.Servers[i]
			srv = &s
		}
	}
	if srv == nil {
		a.errMsg = "Сервер не выбран"
		a.mu.Unlock()
		return
	}
	a.status, a.errMsg = "connecting", ""
	if h := bestIfNow(); h != 0 {
		a.physHint = h
	}
	a.up, a.down, a.upTotal, a.downTotal, a.hist, a.histSeq = 0, 0, 0, 0, nil, 0
	settings := a.p.Settings
	ctx, cancel := context.WithCancel(context.Background())
	a.cancel = cancel
	a.mu.Unlock()
	go func() {
		err := a.connect(ctx, *srv, settings)
		if err != nil {
			a.log("ошибка: " + err.Error())
			a.stopAll()
			a.mu.Lock()
			if ctx.Err() == nil {
				a.errMsg = err.Error()
			}
			a.mu.Unlock()
		}
	}()
}

func (a *App) connect(ctx context.Context, srv core.Server, s core.Settings) error {
	if core.IsFullTunnel(srv.Outbound) {
		return a.connectFullTunnel(ctx, srv)
	}
	var proxy map[string]any
	if srv.Type == "qWDTT" {
		q, err := core.QwdttFromOutbound(srv.Outbound)
		if err != nil {
			return err
		}
		ep, err := a.startQwdtt(ctx, q)
		if err != nil {
			return err
		}
		proxy = ep
	} else if core.IsXray(srv.Outbound) {
		x, err := a.startXray("main", []json.RawMessage{srv.Outbound}, pingNet{})
		if err != nil {
			return err
		}
		a.mu.Lock()
		a.xr = x
		a.mu.Unlock()
		a.log("Xray: XHTTP через локальный SOCKS5")
		proxy = socksOut(x.ports[0])
		go func() {
			<-x.done
			a.mu.Lock()
			if a.xr == x && (a.status == "connected" || a.status == "connecting") {
				a.errMsg = "Xray завершился: " + x.lastErr()
				a.mu.Unlock()
				a.stopAll()
				return
			}
			a.mu.Unlock()
		}()
	} else if err := json.Unmarshal(srv.Outbound, &proxy); err != nil {
		return err
	}
	a.clashAddr = fmt.Sprintf("127.0.0.1:%d", freePort())
	cfg, err := core.BuildConfig(proxy, s, a.clashAddr, ruleDir(a.binDir))
	if err != nil {
		return err
	}
	path := filepath.Join(a.dataDir, "config.json")
	os.WriteFile(path, cfg, 0o600)
	pr, pw := io.Pipe()
	cmd, err := startCore(a, path, s.Mode != "proxy", pw)
	if err != nil {
		return err
	}
	a.mu.Lock()
	a.box = cmd
	a.mu.Unlock()
	var tail []string
	var tmu sync.Mutex
	go func() {
		sc := bufio.NewScanner(pr)
		for sc.Scan() {
			l := sc.Text()
			tmu.Lock()
			tail = append(tail, l)
			if len(tail) > 8 {
				tail = tail[1:]
			}
			tmu.Unlock()
			a.log("[core] " + l)
		}
	}()
	exited := make(chan error, 1)
	go func() { e := cmd.Wait(); pw.Close(); exited <- e }()
	cl := &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}}
	deadline := time.Now().Add(20 * time.Second)
	for {
		select {
		case <-ctx.Done():
			return nil
		case e := <-exited:
			tmu.Lock()
			t := strings.Join(tail, "\n")
			tmu.Unlock()
			return fmt.Errorf("ядро завершилось (%v): %s", e, lastLines(t, 3))
		default:
		}
		if r, err := cl.Get("http://" + a.clashAddr + "/version"); err == nil {
			r.Body.Close()
			break
		}
		if time.Now().After(deadline) {
			return errors.New("ядро не ответило за 20 с")
		}
		time.Sleep(150 * time.Millisecond)
	}
	if s.Mode == "proxy" && !a.Service {
		port := s.ProxyPort
		if port == 0 {
			port = 2080
		}
		if err := setSystemProxy(true, port); err != nil {
			a.log("системный прокси: " + err.Error())
		}
		a.mu.Lock()
		a.proxySet = true
		a.mu.Unlock()
	}
	a.mu.Lock()
	a.status = "connected"
	a.since = time.Now().Unix()
	a.mu.Unlock()
	a.log("подключено: " + srv.Name)
	go a.trafficLoop(ctx)
	go a.healthCheck(ctx, srv, s)
	go a.autoSwitchLoop(ctx, srv, s)
	go func() {
		select {
		case <-ctx.Done():
		case e := <-exited:
			a.mu.Lock()
			if a.status == "connected" {
				tmu.Lock()
				a.errMsg = "Соединение прервано: ядро завершилось (" + fmt.Sprint(e) + ") " + lastLines(strings.Join(tail, "\n"), 2)
				tmu.Unlock()
			}
			a.mu.Unlock()
			a.stopAll()
		}
	}()
	return nil
}

func (a *App) trafficLoop(ctx context.Context) {
	cl := &http.Client{Transport: &http.Transport{Proxy: nil}}
	for ctx.Err() == nil {
		req, _ := http.NewRequestWithContext(ctx, "GET", "http://"+a.clashAddr+"/traffic", nil)
		r, err := cl.Do(req)
		if err != nil {
			time.Sleep(time.Second)
			continue
		}
		dec := json.NewDecoder(r.Body)
		for {
			var t struct{ Up, Down int64 }
			if dec.Decode(&t) != nil {
				break
			}
			a.mu.Lock()
			a.up, a.down = t.Up, t.Down
			a.upTotal += t.Up
			a.downTotal += t.Down
			a.hist = append(a.hist, [2]int64{t.Up, t.Down})
			a.histSeq++
			if len(a.hist) > 120 {
				a.hist = a.hist[len(a.hist)-120:]
			}
			a.mu.Unlock()
		}
		r.Body.Close()
	}
}

func (a *App) startQwdtt(ctx context.Context, q core.Qwdtt) (map[string]any, error) {
	work := filepath.Join(a.dataDir, "qwdtt")
	os.MkdirAll(work, 0o700)
	conf := filepath.Join(work, "wg-turn.conf")
	os.Remove(conf)
	dev := q.DeviceID
	if dev == "" {
		dev = a.p.DeviceID
	}
	dns := pickDNS(q)
	a.log(fmt.Sprintf("qWDTT: старт, потоков %d, DNS %s", q.EffectiveWorkers(), dns))
	args := q.RelayArgs(dev, dns)
	if CaptchaUI {
		// "auto": qwdtt's Go solver first, then a manual WebView request the UI shows
		for i := range args {
			if args[i] == "-captcha-mode" && i+1 < len(args) {
				args[i+1] = "auto"
			}
		}
	}
	cmd := exec.Command(a.bin("qwdtt"), args...)
	cmd.Dir = work
	hideWindow(cmd)
	stdin, _ := cmd.StdinPipe()
	pr, pw := io.Pipe()
	cmd.Stdout, cmd.Stderr = pw, pw
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("qWDTT: движок не найден: %w", err)
	}
	attachJob(cmd)
	a.mu.Lock()
	a.qw, a.qwStdin = cmd, stdin
	a.mu.Unlock()
	secrets := append([]string{q.Password}, q.Hashes...)
	var fatal string
	var fmu sync.Mutex
	var tail []string
	go func() {
		sc := bufio.NewScanner(pr)
		sc.Buffer(make([]byte, 64<<10), 1<<20)
		for sc.Scan() {
			l := sc.Text()
			if a.qwdttCaptchaLine(l) {
				continue
			}
			for _, s := range secrets {
				if s != "" {
					l = strings.ReplaceAll(l, s, "***")
				}
			}
			fmu.Lock()
			if f := core.QwdttFatal(l); f != "" && fatal == "" {
				fatal = f
			}
			tail = append(tail, l)
			if len(tail) > 5 {
				tail = tail[1:]
			}
			fmu.Unlock()
			a.log("[qwdtt] " + l)
		}
	}()
	exited := make(chan struct{})
	go func() { cmd.Wait(); pw.Close(); close(exited) }()
	deadline := time.Now().Add(120 * time.Second)
	for {
		fmu.Lock()
		f := fatal
		t := strings.Join(tail, " | ")
		fmu.Unlock()
		if f != "" {
			return nil, errors.New(f)
		}
		select {
		case <-exited:
			return nil, errors.New("qWDTT: клиент завершился. " + t)
		case <-ctx.Done():
			return nil, errors.New("отменено")
		default:
		}
		if st, err := os.Stat(conf); err == nil && st.Size() > 0 {
			time.Sleep(200 * time.Millisecond)
			b, _ := os.ReadFile(conf)
			os.Remove(conf)
			ep, err := core.WgEndpoint(string(b))
			if err != nil {
				return nil, err
			}
			// endpoint is the local relay; force loopback
			ep["peers"].([]any)[0].(map[string]any)["address"] = "127.0.0.1"
			ep["peers"].([]any)[0].(map[string]any)["port"] = q.LocalPort
			a.log("qWDTT: конфиг получен")
			go func() {
				<-exited
				a.mu.Lock()
				if a.status == "connected" || a.status == "connecting" {
					a.errMsg = "qWDTT: клиент завершился"
				}
				a.mu.Unlock()
				a.stopAll()
			}()
			return ep, nil
		}
		if time.Now().After(deadline) {
			return nil, errors.New("qWDTT: сервер не выдал конфиг за 120 с. " + t)
		}
		time.Sleep(250 * time.Millisecond)
	}
}

func (a *App) Disconnect() {
	a.mu.Lock()
	if a.status == "disconnected" {
		a.mu.Unlock()
		return
	}
	a.status = "disconnecting"
	a.mu.Unlock()
	a.stopAll()
}

func (a *App) stopAll() {
	a.mu.Lock()
	if a.cancel != nil {
		a.cancel()
		a.cancel = nil
	}
	if a.proxySet {
		a.proxySet = false
		setSystemProxy(false, 0)
	}
	box, qw, qin, xr := a.box, a.qw, a.qwStdin, a.xr
	a.box, a.qw, a.qwStdin, a.xr, a.captcha = nil, nil, nil, nil, nil
	a.mu.Unlock()
	if xr != nil {
		defer xr.Stop()
	}
	a.stopFullTunnel()
	if box != nil {
		box.Stop()
	}
	if qin != nil {
		qin.Close()
	}
	if qw != nil && qw.Process != nil {
		qw.Process.Kill()
	}
	a.mu.Lock()
	if a.status != "disconnected" {
		a.logLocked("отключено")
	}
	a.status = "disconnected"
	a.since = 0
	a.up, a.down = 0, 0
	a.mu.Unlock()
}

// sorting helper exposed for completeness (UI sorts client-side)
var _ = sort.Strings

// dropOpenVPN removes OpenVPN servers left by Nox 0.8.x state files (no OpenVPN in 1.0).
func dropOpenVPN(l []core.Server) []core.Server {
	out := l[:0:0]
	for _, s := range l {
		if !core.IsLegacyOpenVPN(s.Outbound) {
			out = append(out, s)
		}
	}
	return out
}

// coreLabel: bundled engines shown under Settings (SSTP uses the OS client: Windows RAS, sstpc).
func coreLabel() string {
	l := "sing-box 1.14.3 · Xray 26.3.27 · qWDTT 1.4.4"
	if runtime.GOOS != "android" {
		l += " · SSTP"
	}
	return l
}
