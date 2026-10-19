package engine

// Profile transfer phone → TV over the local network («Принять с телефона» / «Передать на ТВ»).
//
// Receiver (TV, or any device): PairStart opens a short-lived HTTP listener on a random port,
// shows nox://pair?h=<lan ip>:<port>&t=<token> as a QR plus a 6-digit code for manual entry,
// and stops after one successful import, 5 failed attempts or 5 minutes.
//
// Sender (phone): PairSend fetches the receiver's ephemeral X25519 key, derives
//
//	key = HKDF-SHA256(X25519(eph, tvPub), salt = secret, info = "nox-pair-v1"|tvPub|phonePub)
//
// where secret is the 128-bit QR token, or PBKDF2(code, session salt) for manual entry, and
// POSTs the profiles sealed with AES-256-GCM. A request that does not decrypt (wrong/absent
// token or code) is rejected with 403 and counted. Passive listeners on the LAN learn nothing;
// the QR token also defeats an active attacker, the 6-digit code limits one to 5 online guesses.

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/hkdf"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"nox/core"
)

const (
	pairPath     = "/nox/pair"
	pairTTL      = 5 * time.Minute
	pairMaxFails = 5
	pairIter     = 200_000
)

var b64 = base64.RawURLEncoding

// LanExclude4: private IPv4 ranges kept out of the Android TUN (all of RFC 1918 + link-local
// except 172.19.0.0/16, where the TUN itself lives).
var LanExclude4 = []string{"10.0.0.0/8", "192.168.0.0/16", "169.254.0.0/16",
	"172.16.0.0/15", "172.18.0.0/16", "172.20.0.0/14", "172.24.0.0/13"}

// LanAddrs, when set (Android: from the Kotlin host, where net.Interfaces is restricted),
// returns candidate LAN IPv4 addresses of physical interfaces.
var LanAddrs func() []string

type PairInfo struct {
	Active  bool        `json:"active"`
	Host    string      `json:"host"`  // best LAN address
	Hosts   []string    `json:"hosts"` // all candidates
	Port    int         `json:"port"`
	Token   string      `json:"token"`
	Code    string      `json:"code"`
	URI     string      `json:"uri"`
	Expires int64       `json:"expires"`
	Result  *PairResult `json:"result"`
	Error   string      `json:"error"`
}

type PairResult struct {
	Subs     int    `json:"subs"`
	Servers  int    `json:"servers"`
	Dups     int    `json:"dups"`
	Selected bool   `json:"selected"`
	Settings bool   `json:"settings"`
	From     string `json:"from"`
	Msg      string `json:"msg"`
}

// PairOpts: what the phone sends. SubIDs nil = all subscriptions.
type PairOpts struct {
	SubIDs   []string `json:"subIds"`
	Manual   bool     `json:"manual"`
	Selected bool     `json:"selected"`
	Settings bool     `json:"settings"`
}

type pairSub struct {
	Sub
	Servers []core.Server `json:"servers"`
}

type pairSel struct {
	SubURL string `json:"subUrl,omitempty"`
	Name   string `json:"name"`
	Link   string `json:"link,omitempty"`
}

type pairPayload struct {
	V        int            `json:"v"`
	From     string         `json:"from"`
	Subs     []pairSub      `json:"subs"`
	Servers  []core.Server  `json:"servers"`
	Selected *pairSel       `json:"selected,omitempty"`
	Settings *core.Settings `json:"settings,omitempty"`
}

type pairHello struct {
	V    int    `json:"v"`
	Pub  string `json:"pub"`
	Salt string `json:"salt"`
}

type pairMsg struct {
	V     int    `json:"v"`
	Mode  string `json:"m"` // "t" token | "c" code
	Pub   string `json:"pub"`
	Nonce string `json:"n"`
	CT    string `json:"ct"`
}

type pairRx struct {
	mu      sync.Mutex
	srv     *http.Server
	priv    *ecdh.PrivateKey
	token   []byte
	code    string
	codeKey []byte
	salt    []byte
	info    PairInfo
	fails   int
	stopped bool
}

var (
	pairMu sync.Mutex
	pairCu *pairRx
)

func pairCodeKey(code string, salt []byte) []byte {
	k, _ := pbkdf2.Key(sha256.New, code, salt, pairIter, 32)
	return k
}

func pairKey(shared, secret, tvPub, phPub []byte) ([]byte, error) {
	info := append(append([]byte("nox-pair-v1|"), tvPub...), phPub...)
	return hkdf.Key(sha256.New, shared, secret, string(info), 32)
}

func gcm(key []byte) (cipher.AEAD, error) {
	b, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(b)
}

func isLanIP(ip net.IP) bool {
	return ip != nil && (ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast())
}

// lanHosts: private IPv4 of physical interfaces, best first (192.168 > 10 > 172.16/12).
func lanHosts() []string {
	var c []string
	if LanAddrs != nil {
		c = LanAddrs()
	} else if ifs, err := net.Interfaces(); err == nil {
		for _, i := range ifs {
			n := strings.ToLower(i.Name)
			if i.Flags&net.FlagUp == 0 || i.Flags&net.FlagLoopback != 0 || strings.HasPrefix(n, "nox") ||
				strings.HasPrefix(n, "tun") || strings.HasPrefix(n, "utun") || strings.HasPrefix(n, "wg") ||
				strings.HasPrefix(n, "ppp") || strings.HasPrefix(n, "docker") || strings.HasPrefix(n, "veth") {
				continue
			}
			as, _ := i.Addrs()
			for _, a := range as {
				if ipn, ok := a.(*net.IPNet); ok {
					c = append(c, ipn.IP.String())
				}
			}
		}
	}
	var out []string
	seen := map[string]bool{}
	for _, h := range c {
		ip := net.ParseIP(strings.TrimSpace(strings.Split(h, "/")[0])).To4()
		if ip == nil || !ip.IsPrivate() || (ip[0] == 172 && ip[1] == 19 && ip[2] == 0) || seen[ip.String()] {
			continue // 172.19.0.0/30 is our own TUN
		}
		seen[ip.String()] = true
		out = append(out, ip.String())
	}
	rank := func(s string) int {
		switch {
		case strings.HasPrefix(s, "192.168."):
			return 0
		case strings.HasPrefix(s, "10."):
			return 1
		}
		return 2
	}
	sort.SliceStable(out, func(i, j int) bool { return rank(out[i]) < rank(out[j]) })
	return out
}

// PairStart starts (or restarts) the receiver and returns what to show.
func (a *App) PairStart() (PairInfo, error) {
	a.PairStop()
	priv, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return PairInfo{}, err
	}
	ln, err := net.Listen("tcp4", "0.0.0.0:0")
	if err != nil {
		return PairInfo{}, fmt.Errorf("не удалось открыть порт: %w", err)
	}
	tok := make([]byte, 16)
	rand.Read(tok)
	salt := make([]byte, 16)
	rand.Read(salt)
	n, _ := rand.Int(rand.Reader, big.NewInt(1_000_000))
	code := fmt.Sprintf("%06d", n.Int64())
	hosts := lanHosts()
	port := ln.Addr().(*net.TCPAddr).Port
	r := &pairRx{priv: priv, token: tok, code: code, salt: salt, codeKey: pairCodeKey(code, salt)}
	r.info = PairInfo{Active: true, Hosts: hosts, Port: port, Token: b64.EncodeToString(tok), Code: code,
		Expires: time.Now().Add(pairTTL).Unix()}
	if len(hosts) > 0 {
		r.info.Host = hosts[0]
		r.info.URI = fmt.Sprintf("nox://pair?h=%s:%d&t=%s", hosts[0], port, r.info.Token)
	} else {
		r.info.Error = "Нет подключения к локальной сети. Подключите устройство к Wi‑Fi или Ethernet."
	}
	mux := http.NewServeMux()
	mux.HandleFunc(pairPath, func(w http.ResponseWriter, q *http.Request) { a.pairServe(r, w, q) })
	r.srv = &http.Server{Handler: mux, ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 30 * time.Second}
	pairMu.Lock()
	pairCu = r
	pairMu.Unlock()
	go r.srv.Serve(ln)
	time.AfterFunc(pairTTL, func() {
		r.stop("Время ожидания истекло. Откройте «Принять с телефона» снова.")
	})
	a.log(fmt.Sprintf("приём профилей: %v порт %d", hosts, port))
	return r.status(), nil
}

func (r *pairRx) status() PairInfo {
	r.mu.Lock()
	defer r.mu.Unlock()
	i := r.info
	i.Hosts = append([]string(nil), i.Hosts...)
	return i
}

func (r *pairRx) stop(msg string) {
	r.mu.Lock()
	if r.stopped {
		r.mu.Unlock()
		return
	}
	r.stopped = true
	r.info.Active = false
	if msg != "" && r.info.Result == nil {
		r.info.Error = msg
	}
	srv := r.srv
	r.mu.Unlock()
	go func() { time.Sleep(300 * time.Millisecond); srv.Close() }() // let the reply flush
}

// PairStatus: polled by the receive screen.
func (a *App) PairStatus() PairInfo {
	pairMu.Lock()
	r := pairCu
	pairMu.Unlock()
	if r == nil {
		return PairInfo{}
	}
	return r.status()
}

func (a *App) PairStop() {
	pairMu.Lock()
	r := pairCu
	pairCu = nil
	pairMu.Unlock()
	if r != nil {
		r.stop("")
	}
}

func pairJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func (a *App) pairServe(r *pairRx, w http.ResponseWriter, q *http.Request) {
	host, _, _ := net.SplitHostPort(q.RemoteAddr)
	if !isLanIP(net.ParseIP(host)) {
		pairJSON(w, 403, map[string]string{"e": "only LAN"})
		return
	}
	r.mu.Lock()
	stopped := r.stopped
	r.mu.Unlock()
	if stopped {
		pairJSON(w, 410, map[string]string{"e": "closed"})
		return
	}
	switch q.Method {
	case http.MethodGet:
		pairJSON(w, 200, pairHello{V: 1, Pub: b64.EncodeToString(r.priv.PublicKey().Bytes()), Salt: b64.EncodeToString(r.salt)})
	case http.MethodPost:
		var m pairMsg
		body, err := io.ReadAll(io.LimitReader(q.Body, 16<<20))
		if err != nil || json.Unmarshal(body, &m) != nil {
			pairJSON(w, 400, map[string]string{"e": "bad request"})
			return
		}
		pl, err := r.open(m)
		if err != nil {
			r.mu.Lock()
			r.fails++
			f := r.fails
			r.mu.Unlock()
			a.log("приём профилей: отклонён запрос с неверным ключом от " + host)
			if f >= pairMaxFails {
				r.stop("Слишком много неверных попыток. Откройте «Принять с телефона» снова.")
			}
			pairJSON(w, 403, map[string]string{"e": "bad token"})
			return
		}
		res := a.importPair(pl)
		r.mu.Lock()
		r.info.Result = &res
		r.info.Error = ""
		r.mu.Unlock()
		r.stop("")
		pairJSON(w, 200, res)
	default:
		pairJSON(w, 405, map[string]string{"e": "method"})
	}
}

func (r *pairRx) open(m pairMsg) (*pairPayload, error) {
	ph, err1 := b64.DecodeString(m.Pub)
	nonce, err2 := b64.DecodeString(m.Nonce)
	ct, err3 := b64.DecodeString(m.CT)
	if err1 != nil || err2 != nil || err3 != nil || m.V != 1 {
		return nil, errors.New("bad message")
	}
	peer, err := ecdh.X25519().NewPublicKey(ph)
	if err != nil {
		return nil, err
	}
	shared, err := r.priv.ECDH(peer)
	if err != nil {
		return nil, err
	}
	secret := r.token
	if m.Mode == "c" {
		secret = r.codeKey
	} else if m.Mode != "t" {
		return nil, errors.New("bad mode")
	}
	key, err := pairKey(shared, secret, r.priv.PublicKey().Bytes(), ph)
	if err != nil {
		return nil, err
	}
	g, err := gcm(key)
	if err != nil || len(nonce) != g.NonceSize() {
		return nil, errors.New("bad nonce")
	}
	pt, err := g.Open(nil, nonce, ct, []byte("nox-pair-v1"))
	if err != nil {
		return nil, err
	}
	var p pairPayload
	if err := json.Unmarshal(pt, &p); err != nil || p.V != 1 {
		return nil, errors.New("bad payload")
	}
	return &p, nil
}

func normSubURL(u string) string {
	u = strings.TrimSpace(u)
	if p, err := url.Parse(u); err == nil && p.Host != "" {
		p.Scheme, p.Host = strings.ToLower(p.Scheme), strings.ToLower(p.Host)
		u = p.String()
	}
	return strings.TrimRight(u, "/")
}

func outKey(o json.RawMessage) string {
	var b bytes.Buffer
	if json.Compact(&b, o) != nil {
		return string(o)
	}
	// tags differ between devices; compare without them
	var m map[string]any
	if json.Unmarshal(b.Bytes(), &m) == nil {
		delete(m, "tag")
		if k, err := json.Marshal(m); err == nil {
			return string(k)
		}
	}
	return b.String()
}

func plural(n int, one, few, many string) string {
	m10, m100 := n%10, n%100
	switch {
	case m10 == 1 && m100 != 11:
		return one
	case m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14):
		return few
	}
	return many
}

// importPair merges received profiles: subscriptions dedup by URL, manual servers by config.
func (a *App) importPair(p *pairPayload) PairResult {
	res := PairResult{From: p.From}
	var fresh []Sub
	a.mu.Lock()
	haveSub := map[string]string{}
	for _, s := range a.p.Subs {
		haveSub[normSubURL(s.URL)] = s.ID
	}
	haveSrv := map[string]string{}
	for _, s := range a.p.Servers {
		if s.SubID == "" {
			haveSrv[outKey(s.Outbound)] = s.ID
		}
	}
	firstNew := ""
	for _, ps := range p.Subs {
		k := normSubURL(ps.URL)
		if ps.URL == "" {
			continue
		}
		if _, ok := haveSub[k]; ok {
			res.Dups++
			continue
		}
		sub := ps.Sub
		sub.ID = newID()
		haveSub[k] = sub.ID
		a.p.Subs = append(a.p.Subs, sub)
		fresh = append(fresh, sub)
		res.Subs++
		for _, s := range ps.Servers {
			if s.Type == "openvpn" {
				continue
			}
			s.ID, s.SubID, s.Ping = newID(), sub.ID, 0
			a.p.Servers = append(a.p.Servers, s)
			res.Servers++
			if firstNew == "" && s.Type != core.BalancerType {
				firstNew = s.ID
			}
		}
	}
	for _, s := range p.Servers {
		k := outKey(s.Outbound)
		if len(s.Outbound) == 0 || s.Type == "openvpn" {
			continue
		}
		if _, ok := haveSrv[k]; ok {
			res.Dups++
			continue
		}
		s.ID, s.SubID, s.Ping = newID(), "", 0
		haveSrv[k] = s.ID
		a.p.Servers = append(a.p.Servers, s)
		res.Servers++
		if firstNew == "" {
			firstNew = s.ID
		}
	}
	if p.Selected != nil {
		for _, s := range a.p.Servers {
			if p.Selected.Link != "" && s.SubID == "" && outKey(s.Outbound) == outKey(json.RawMessage(p.Selected.Link)) ||
				p.Selected.SubURL != "" && s.SubID == haveSub[normSubURL(p.Selected.SubURL)] && s.Name == p.Selected.Name {
				a.p.Selected = s.ID
				res.Selected = true
				break
			}
		}
	}
	if (a.p.Selected == "" || !a.hasServerLocked(a.p.Selected)) && firstNew != "" {
		a.p.Selected = firstNew
	}
	if p.Settings != nil {
		s, in := a.p.Settings, *p.Settings
		// portable preferences only (not ports, autostart, split apps, UI scale of this screen)
		s.Mode, s.DNS, s.CustomDNS, s.DirectRU, s.BlockAds, s.IPv6 = in.Mode, in.DNS, in.CustomDNS, in.DirectRU, in.BlockAds, in.IPv6
		s.PingMode, s.PingURL, s.Sniff, s.AutoSwitch, s.Theme = in.PingMode, in.PingURL, in.Sniff, in.AutoSwitch, in.Theme
		if s.Mode != "proxy" {
			s.Mode = "tun"
		}
		a.p.Settings = s
		res.Settings = true
	}
	a.save()
	a.mu.Unlock()
	res.Msg = fmt.Sprintf("Получено: %d %s, %d %s", res.Subs, plural(res.Subs, "подписка", "подписки", "подписок"),
		res.Servers, plural(res.Servers, "сервер", "сервера", "серверов"))
	if res.Dups > 0 {
		res.Msg += fmt.Sprintf(" · уже были: %d", res.Dups)
	}
	a.log("приём профилей: " + res.Msg)
	for i := range fresh { // refresh in the background; the transferred servers work meanwhile
		go a.fetchSub(&fresh[i], false)
	}
	return res
}

// ---------------------------------------------------------------- sender (phone)

// ParsePairTarget: nox://pair?h=host:port&t=token, or a typed "host:port" / "host port".
func ParsePairTarget(s string) (hostport, token string, err error) {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(strings.ToLower(s), "nox://") {
		u, e := url.Parse(s)
		if e != nil {
			return "", "", errors.New("неверный QR-код")
		}
		hostport, token = u.Query().Get("h"), u.Query().Get("t")
	} else {
		hostport = strings.Join(strings.Fields(strings.ReplaceAll(s, "：", ":")), ":")
	}
	h, p, e := net.SplitHostPort(hostport)
	if e != nil || net.ParseIP(h) == nil {
		return "", "", errors.New("Введите адрес как на экране ТВ, например 192.168.1.20:41234")
	}
	if n, e := strconv.Atoi(p); e != nil || n <= 0 || n > 65535 {
		return "", "", errors.New("неверный порт")
	}
	if !isLanIP(net.ParseIP(h)) {
		return "", "", errors.New("адрес должен быть в локальной сети")
	}
	return hostport, token, nil
}

func pairNetErr(hp string, err error) error {
	var ne net.Error
	if errors.As(err, &ne) || errors.Is(err, os.ErrDeadlineExceeded) || strings.Contains(err.Error(), "connect") {
		return fmt.Errorf("ТВ не отвечает (%s). Подключите оба устройства к одной Wi‑Fi сети; "+
			"если не помогает — на роутере может быть включена изоляция клиентов (гостевая сеть)", hp)
	}
	return err
}

// PairSend sends the chosen profiles to a receiver. target: QR text or "ip:port"; code: the
// 6-digit code when typed manually (ignored when the QR has a token).
func (a *App) PairSend(target, code string, o PairOpts) (PairResult, error) {
	hp, tok, err := ParsePairTarget(target)
	if err != nil {
		return PairResult{}, err
	}
	code = strings.Join(strings.Fields(code), "")
	if tok == "" && (len(code) != 6 || strings.Trim(code, "0123456789") != "") {
		return PairResult{}, errors.New("Введите 6-значный код с экрана ТВ")
	}
	pl := a.pairPayload(o)
	if len(pl.Subs) == 0 && len(pl.Servers) == 0 && pl.Settings == nil {
		return PairResult{}, errors.New("Нечего передавать: добавьте подписку или сервер")
	}
	cl := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{Proxy: nil,
		DialContext: (&net.Dialer{Timeout: 6 * time.Second}).DialContext}}
	base := "http://" + hp + pairPath
	resp, err := cl.Get(base)
	if err != nil {
		return PairResult{}, pairNetErr(hp, err)
	}
	var hello pairHello
	err = json.NewDecoder(io.LimitReader(resp.Body, 1<<16)).Decode(&hello)
	resp.Body.Close()
	if resp.StatusCode == 410 {
		return PairResult{}, errors.New("Приём на ТВ уже закрыт. Откройте «Принять с телефона» снова")
	}
	if err != nil || resp.StatusCode != 200 || hello.V != 1 {
		return PairResult{}, fmt.Errorf("по адресу %s не Nox (HTTP %d)", hp, resp.StatusCode)
	}
	tvPub, err1 := b64.DecodeString(hello.Pub)
	salt, err2 := b64.DecodeString(hello.Salt)
	peer, err3 := ecdh.X25519().NewPublicKey(tvPub)
	if err1 != nil || err2 != nil || err3 != nil {
		return PairResult{}, errors.New("неверный ответ ТВ")
	}
	mode, secret := "t", []byte(nil)
	if tok != "" {
		if secret, err = b64.DecodeString(tok); err != nil || len(secret) != 16 {
			return PairResult{}, errors.New("неверный QR-код")
		}
	} else {
		mode, secret = "c", pairCodeKey(code, salt)
	}
	eph, _ := ecdh.X25519().GenerateKey(rand.Reader)
	shared, err := eph.ECDH(peer)
	if err != nil {
		return PairResult{}, err
	}
	key, _ := pairKey(shared, secret, tvPub, eph.PublicKey().Bytes())
	g, _ := gcm(key)
	nonce := make([]byte, g.NonceSize())
	rand.Read(nonce)
	pt, _ := json.Marshal(pl)
	msg, _ := json.Marshal(pairMsg{V: 1, Mode: mode, Pub: b64.EncodeToString(eph.PublicKey().Bytes()),
		Nonce: b64.EncodeToString(nonce), CT: b64.EncodeToString(g.Seal(nil, nonce, pt, []byte("nox-pair-v1")))})
	resp, err = cl.Post(base, "application/json", bytes.NewReader(msg))
	if err != nil {
		return PairResult{}, pairNetErr(hp, err)
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case 200:
		var r PairResult
		json.NewDecoder(io.LimitReader(resp.Body, 1<<16)).Decode(&r)
		a.log("передача профилей на " + hp + ": " + r.Msg)
		return r, nil
	case 403:
		if mode == "c" {
			return PairResult{}, errors.New("Неверный код. Проверьте 6 цифр на экране ТВ")
		}
		return PairResult{}, errors.New("QR-код устарел. Откройте «Принять с телефона» на ТВ заново")
	case 410:
		return PairResult{}, errors.New("Приём на ТВ уже закрыт. Откройте «Принять с телефона» снова")
	}
	return PairResult{}, fmt.Errorf("ТВ ответил HTTP %d", resp.StatusCode)
}

// PairPreview: counts for the «что передать» screen.
func (a *App) pairPayload(o PairOpts) pairPayload {
	a.mu.Lock()
	defer a.mu.Unlock()
	h, _ := os.Hostname()
	p := pairPayload{V: 1, From: strings.TrimSpace(osName() + " " + h)}
	want := map[string]bool{}
	for _, id := range o.SubIDs {
		want[id] = true
	}
	subURL := map[string]string{}
	for _, s := range a.p.Subs {
		subURL[s.ID] = s.URL
		if o.SubIDs != nil && !want[s.ID] {
			continue
		}
		ps := pairSub{Sub: s}
		ps.ID = ""
		for _, sv := range a.p.Servers {
			if sv.SubID == s.ID {
				sv.ID, sv.SubID, sv.Ping = "", "", 0
				ps.Servers = append(ps.Servers, sv)
			}
		}
		p.Subs = append(p.Subs, ps)
	}
	if o.Manual {
		for _, sv := range a.p.Servers {
			if sv.SubID == "" {
				sv.ID, sv.Ping = "", 0
				p.Servers = append(p.Servers, sv)
			}
		}
	}
	if o.Selected {
		for _, sv := range a.p.Servers {
			if sv.ID == a.p.Selected {
				if sv.SubID == "" {
					p.Selected = &pairSel{Name: sv.Name, Link: string(sv.Outbound)}
				} else {
					p.Selected = &pairSel{Name: sv.Name, SubURL: subURL[sv.SubID]}
				}
			}
		}
	}
	if o.Settings {
		s := a.p.Settings
		p.Settings = &s
	}
	return p
}
