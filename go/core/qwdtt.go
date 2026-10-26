package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

type Qwdtt struct {
	Name      string   `json:"-"`
	Type      string   `json:"type"`
	Peer      string   `json:"peer"`
	Hashes    []string `json:"hashes"`
	Password  string   `json:"password"`
	Workers   int      `json:"workers"`
	LocalPort int      `json:"local_port"`
	DeviceID  string   `json:"device_id,omitempty"`
	GoDNS     string   `json:"go_dns,omitempty"`
	Obfs      string   `json:"obfs,omitempty"`
	TurnTCP   bool     `json:"turn_tcp,omitempty"`
}

const QwdttType = "_qwdtt"

func (q Qwdtt) Outbound() map[string]any {
	b, _ := json.Marshal(q)
	var m map[string]any
	json.Unmarshal(b, &m)
	return m
}

func (q Qwdtt) EffectiveWorkers() int {
	h := len(q.Hashes)
	if h < 1 {
		h = 1
	}
	if h > 4 {
		h = 4
	}
	max := h * 27
	n := q.Workers
	if n < 9 {
		n = 9
	}
	if n > max {
		n = max
	}
	return n / 9 * 9
}

func ensurePort(peer string, def int) string {
	t := strings.TrimSpace(peer)
	has := false
	if strings.HasPrefix(t, "[") {
		has = strings.Contains(t, "]:")
	} else {
		has = strings.Count(t, ":") == 1
	}
	if has {
		return t
	}
	if strings.Contains(t, ":") && !strings.HasPrefix(t, "[") {
		return fmt.Sprintf("[%s]:%d", t, def)
	}
	return fmt.Sprintf("%s:%d", t, def)
}

// ParseQwdtt parses qwdtt://config?name=…&peer=host:port&hashes=h1,h2&pass=…&workers=16&port=9000. Errors never contain secrets.
func ParseQwdtt(link string) (Qwdtt, error) {
	t := strings.TrimSpace(link)
	body := strings.TrimPrefix(t[strings.Index(t, ":")+1:], "//")
	query, frag := "", ""
	if i := strings.Index(body, "?"); i >= 0 {
		query = body[i+1:]
	}
	if i := strings.Index(query, "#"); i >= 0 {
		frag = query[i+1:]
		query = query[:i]
	} else if i := strings.Index(body, "#"); i >= 0 {
		frag = body[i+1:]
	}
	vals := map[string]string{}
	for _, kv := range strings.Split(query, "&") {
		if kv == "" {
			continue
		}
		k, v, _ := strings.Cut(kv, "=")
		k, _ = url.QueryUnescape(k)
		if d, err := url.QueryUnescape(v); err == nil {
			v = d
		}
		vals[strings.ToLower(k)] = v
	}
	g := func(keys ...string) string {
		for _, k := range keys {
			if v := strings.TrimSpace(vals[k]); v != "" {
				return v
			}
		}
		return ""
	}
	q := Qwdtt{Type: QwdttType}
	peer := g("peer", "server", "address")
	if peer == "" {
		return q, errors.New("qwdtt: нет peer (адрес сервера)")
	}
	dp := 56000
	if p, err := strconv.Atoi(g("dtls_port", "dtlsport")); err == nil && p > 0 && p < 65536 {
		dp = p
	}
	q.Peer = ensurePort(peer, dp)
	if _, _, err := splitHP(q.Peer); err != nil {
		return q, errors.New("qwdtt: неверный адрес сервера")
	}
	q.Password = g("pass", "password")
	if q.Password == "" {
		return q, errors.New("qwdtt: нет pass (пароль подключения)")
	}
	seen := map[string]bool{}
	for _, h := range strings.FieldsFunc(g("hashes", "hash", "vk"), func(r rune) bool { return r == ',' || r == ' ' || r == '\n' || r == '\t' }) {
		if i := strings.LastIndex(h, "/call/join/"); i >= 0 {
			h = h[i+len("/call/join/"):]
		}
		if i := strings.Index(h, "?"); i >= 0 {
			h = h[:i]
		}
		if h != "" && !seen[h] && len(q.Hashes) < 4 {
			seen[h] = true
			q.Hashes = append(q.Hashes, h)
		}
	}
	if len(q.Hashes) == 0 {
		return q, errors.New("qwdtt: нет hashes (ссылки на звонки VK)")
	}
	q.Workers = 9
	if n, err := strconv.Atoi(g("workers", "n")); err == nil && n > 0 {
		q.Workers = n
	}
	q.LocalPort = 9000
	if n, err := strconv.Atoi(g("port", "listen_port")); err == nil && n >= 1024 && n <= 65535 {
		q.LocalPort = n
	}
	q.DeviceID = g("device_id", "deviceid")
	if d := g("go_dns", "dns"); d != "" && d != "auto" {
		q.GoDNS = d
	}
	if o := strings.ToLower(g("obfs")); o == "video" {
		q.Obfs = o
	}
	q.TurnTCP = truthy(g("turn_tcp", "tcp"))
	q.Name = g("name")
	if q.Name == "" && frag != "" {
		q.Name, _ = url.QueryUnescape(frag)
	}
	if q.Name == "" {
		h, _, _ := splitHP(q.Peer)
		q.Name = "qWDTT " + h
	}
	return q, nil
}

func QwdttFromOutbound(raw []byte) (Qwdtt, error) {
	var q Qwdtt
	if err := json.Unmarshal(raw, &q); err != nil {
		return q, err
	}
	if q.Type != QwdttType {
		return q, errors.New("not qwdtt")
	}
	if q.Workers == 0 {
		q.Workers = 9
	}
	if q.LocalPort == 0 {
		q.LocalPort = 9000
	}
	return q, nil
}

func (q Qwdtt) RelayArgs(deviceID, goDNS string) []string {
	obfs := q.Obfs
	if obfs == "" {
		obfs = "audio"
	}
	a := []string{"-peer", q.Peer, "-vk", strings.Join(q.Hashes, ","), "-password", q.Password, "-device-id", deviceID,
		"-n", strconv.Itoa(q.EffectiveWorkers()), "-listen", fmt.Sprintf("127.0.0.1:%d", q.LocalPort), "-mode", "vpn",
		"-vk-auth", "anonymous", "-vk-anon-path", "vkcalls", "-captcha-mode", "rjs", "-go-dns", goDNS, "-obfs", obfs}
	if q.TurnTCP {
		a = append(a, "-turn-tcp")
	}
	return a
}

func (q Qwdtt) PingArgs(goDNS string) []string {
	a := []string{"-ping-only", "-peer", q.Peer, "-vk", q.Hashes[0], "-password", q.Password, "-go-dns", goDNS, "-vk-auth", "anonymous", "-captcha-mode", "rjs"}
	if q.TurnTCP {
		a = append(a, "-turn-tcp")
	}
	return a
}

// QwdttTransient reports whether a QwdttFatal message is a temporary VK condition
// (flood control / captcha): qwdtt keeps retrying, and an exit after it must auto-restart.
func QwdttTransient(msg string) bool {
	return strings.Contains(msg, "flood control") || strings.Contains(msg, "«я не робот»")
}

func QwdttFatal(line string) string {
	l := strings.ToLower(line)
	switch {
	case strings.Contains(l, "неверный пароль") || strings.Contains(l, "wrong_password"):
		return "qWDTT: неверный пароль подключения"
	case strings.Contains(l, "привязан к другому устройству") || strings.Contains(l, "device_mismatch"):
		return "qWDTT: пароль привязан к другому устройству (лимит устройств)"
	case strings.Contains(l, "срок действия пароля истёк") || strings.Contains(l, "denied:expired"):
		return "qWDTT: срок действия пароля истёк"
	case strings.Contains(l, "denied:deactivated") || strings.Contains(l, "деактивирован"):
		return "qWDTT: пароль деактивирован"
	case strings.Contains(l, "fatal_captcha"):
		return "qWDTT: VK требует проверку «я не робот», а автоматически пройти её не удалось. Попробуйте позже или другой сервер/хэш звонка"
	case strings.Contains(l, "flood control") || strings.Contains(l, "error_code:29") || strings.Contains(l, "error_code=29"):
		return "qWDTT: VK временно ограничил запросы (flood control), попробуйте позже"
	}
	return ""
}

// WgEndpoint converts the wg-quick config issued by the qWDTT server into a sing-box wireguard endpoint.
func WgEndpoint(text string) (map[string]any, error) {
	iface, peer := map[string]string{}, map[string]string{}
	var sec map[string]string
	for _, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(strings.Trim(strings.TrimSpace(raw), "║╔╗╚╝═"))
		if i := strings.Index(line, "#"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		switch {
		case line == "":
		case strings.EqualFold(line, "[Interface]"):
			sec = iface
		case strings.EqualFold(line, "[Peer]"):
			if len(peer) == 0 {
				sec = peer
			} else {
				sec = nil
			}
		case strings.Contains(line, "=") && sec != nil:
			k, v, _ := strings.Cut(line, "=")
			sec[strings.ToLower(strings.TrimSpace(k))] = strings.TrimSpace(v)
		}
	}
	if iface["privatekey"] == "" || peer["publickey"] == "" || peer["endpoint"] == "" {
		return nil, errors.New("wg config: неполный")
	}
	h, p, err := splitHP(peer["endpoint"])
	if err != nil {
		return nil, err
	}
	addr := csv(iface["address"])
	for i, a := range addr {
		if !strings.Contains(a, "/") {
			if strings.Contains(a, ":") {
				addr[i] += "/128"
			} else {
				addr[i] += "/32"
			}
		}
	}
	mtu, _ := strconv.Atoi(iface["mtu"])
	if mtu < 576 || mtu > 1280 {
		mtu = 1280 // VK TURN path: larger packets get fragmented/dropped
	}
	allowed := csv(peer["allowedips"])
	if len(allowed) == 0 {
		allowed = []string{"0.0.0.0/0"}
	}
	pe := map[string]any{"address": h, "port": p, "public_key": peer["publickey"], "allowed_ips": allowed}
	if v := peer["presharedkey"]; v != "" {
		pe["pre_shared_key"] = v
	}
	ka, _ := strconv.Atoi(peer["persistentkeepalive"])
	if ka <= 0 {
		// NAT on the path to VK TURN drops a quiet UDP session in about a minute.
		// 25s is the usual WireGuard keepalive and is harmless on the local relay.
		ka = 25
	}
	pe["persistent_keepalive_interval"] = ka
	return map[string]any{"type": "wireguard", "address": addr, "private_key": iface["privatekey"], "mtu": mtu, "peers": []any{pe}}, nil
}
