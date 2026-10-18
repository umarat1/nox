package core

// SSTP (sstp://) support. A full-tunnel VPN that does not go through sing-box: Windows uses the
// built-in RAS SSTP client. Outbound JSON uses the private type "_sstp".
// Nox 1.0 has no OpenVPN (decision 2026-10-18): .ovpn files and /ovpn subscription pages are
// not parsed, and OpenVPN servers from older state files are dropped on load (LegacyOpenVPN).
//
// sstp:// link format (documented for the server side):
//   sstp://<user>:<password>@<host>[:<port>]?sni=<tls-sni>&insecure=0|1&dns=1.1.1.1,8.8.8.8#<name>
//   - user/password: URL-encoded (percent-encoding), required
//   - port: default 443
//   - sni: optional TLS SNI / cert name (default = host). Windows RAS ignores it (uses host).
//   - insecure=1: skip cert verification (only honoured by sstpc on Linux/macOS)
//   - dns: optional comma-separated DNS servers pushed locally
//   - #name: URL-encoded display name

import (
	"encoding/json"
	"errors"
	"net/url"
	"strconv"
	"strings"
)

const (
	SSTPType = "_sstp"
	// LegacyOpenVPNType marks servers saved by Nox 0.8.x; 1.0 removes them.
	LegacyOpenVPNType = "_openvpn"
)

type SSTP struct {
	Type     string   `json:"type"`
	Server   string   `json:"server"`
	Port     int      `json:"server_port"`
	User     string   `json:"user"`
	Password string   `json:"password"`
	SNI      string   `json:"sni,omitempty"`
	Insecure bool     `json:"insecure,omitempty"`
	DNS      []string `json:"dns,omitempty"`
}

func outboundMap(v any) map[string]any {
	b, _ := json.Marshal(v)
	var m map[string]any
	json.Unmarshal(b, &m)
	return m
}

func ParseSSTP(s string) (Server, error) {
	u, err := url.Parse(strings.TrimSpace(s))
	if err != nil || !strings.EqualFold(u.Scheme, "sstp") {
		return Server{}, errors.New("sstp: неверная ссылка")
	}
	q := SSTP{Type: SSTPType, Server: u.Hostname(), Port: 443}
	if q.Server == "" {
		return Server{}, errors.New("sstp: нет адреса сервера")
	}
	if p := u.Port(); p != "" {
		q.Port, _ = strconv.Atoi(p)
	}
	if u.User != nil {
		q.User = u.User.Username()
		q.Password, _ = u.User.Password()
	}
	if q.User == "" {
		return Server{}, errors.New("sstp: нет логина")
	}
	v := u.Query()
	q.SNI = v.Get("sni")
	q.Insecure = truthy(v.Get("insecure")) || truthy(v.Get("allowInsecure"))
	if d := v.Get("dns"); d != "" {
		q.DNS = csv(d)
	}
	name := u.Fragment
	if name == "" {
		name = "SSTP " + q.Server
	}
	return mk(name, "SSTP", q.Server, q.Port, outboundMap(q))
}

func SSTPFrom(raw []byte) (SSTP, error) {
	var o SSTP
	err := json.Unmarshal(raw, &o)
	if err == nil && o.Type != SSTPType {
		err = errors.New("не SSTP")
	}
	return o, err
}

// IsFullTunnel: servers that bypass sing-box (no URL test / balancer membership).
func IsFullTunnel(raw []byte) bool {
	var t struct{ Type string }
	json.Unmarshal(raw, &t)
	return t.Type == SSTPType
}

// IsLegacyOpenVPN: an OpenVPN server saved by 0.8.x (unsupported in 1.0).
func IsLegacyOpenVPN(raw []byte) bool {
	var t struct{ Type string }
	json.Unmarshal(raw, &t)
	return t.Type == LegacyOpenVPNType
}
