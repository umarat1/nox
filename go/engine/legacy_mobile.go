package engine

import (
	"encoding/json"
	"strings"

	"nox/core"
)

// Nox 0.7.x for Android (com.lumen.vpn) kept everything in files/lumen-data.json
// (kotlinx-serialization of AppData: servers, subscriptions, settings, renames). 1.0
// installs over it with the same package id, so the UI hands that file to ImportLegacy.

type androidData struct {
	Servers []struct {
		ID       string          `json:"id"`
		Name     string          `json:"name"`
		Protocol string          `json:"protocol"`
		Host     string          `json:"host"`
		Port     int             `json:"port"`
		Outbound json.RawMessage `json:"outbound"`
		SubID    *string         `json:"subscriptionId"`
		Latency  *int            `json:"latencyMs"`
	} `json:"servers"`
	Subs []struct {
		ID       string  `json:"id"`
		Name     string  `json:"name"`
		URL      string  `json:"url"`
		Updated  int64   `json:"updatedAt"`
		Upload   int64   `json:"upload"`
		Download int64   `json:"download"`
		Total    int64   `json:"total"`
		Expire   int64   `json:"expire"`
		Announce *string `json:"announce"`
		WebPage  *string `json:"webPageUrl"`
		Support  *string `json:"supportUrl"`
	} `json:"subscriptions"`
	Settings map[string]any `json:"settings"`
}

// sing-box can run these; 0.7.x-only engines (xray, mihomo, OpenFlux, chains, OpenVPN)
// are not part of 1.0. Their subscription servers come back on the next refresh if the
// provider also offers a supported protocol.
var androidKeep = map[string]bool{"vless": true, "vmess": true, "trojan": true, "shadowsocks": true,
	"hysteria": true, "hysteria2": true, "tuic": true, "anytls": true, "wireguard": true, "socks": true,
	"http": true, "ssh": true, "_qwdtt": true, "_sstp": true}

func secs(t int64) int64 {
	if t > 1e12 { // milliseconds
		return t / 1000
	}
	return t
}

func str(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// convertAndroidLegacy returns ok=false if b is not a 0.7.x Android AppData file.
func convertAndroidLegacy(b []byte) (Persist, int, bool) {
	var probe map[string]json.RawMessage
	if json.Unmarshal(b, &probe) != nil || probe["subscriptions"] == nil {
		return Persist{}, 0, false
	}
	var d androidData
	if json.Unmarshal(b, &d) != nil {
		return Persist{}, 0, false
	}
	p := Persist{Settings: core.DefaultSettings()}
	for _, s := range d.Subs {
		if s.URL == "" {
			continue
		}
		p.Subs = append(p.Subs, Sub{ID: s.ID, URL: s.URL, Name: s.Name, Updated: secs(s.Updated),
			Upload: s.Upload, Download: s.Download, Total: s.Total, Expire: secs(s.Expire),
			Announce: str(s.Announce), WebPage: str(s.WebPage), Support: str(s.Support)})
	}
	dropped := 0
	for _, s := range d.Servers {
		ob := s.Outbound
		var str string
		if json.Unmarshal(ob, &str) == nil { // stored as an encoded string
			ob = json.RawMessage(str)
		}
		var t struct {
			Type string `json:"type"`
		}
		if json.Unmarshal(ob, &t) != nil || !androidKeep[t.Type] {
			dropped++
			continue
		}
		srv := core.Server{ID: s.ID, Name: s.Name, Type: core.DisplayType(t.Type), Host: s.Host, Port: s.Port, Outbound: ob}
		if s.SubID != nil {
			srv.SubID = *s.SubID
		}
		if s.Latency != nil {
			srv.Ping = *s.Latency
		}
		p.Servers = append(p.Servers, srv)
	}
	st := d.Settings
	b2 := func(k string, dst *bool) {
		if v, ok := st[k].(bool); ok {
			*dst = v
		}
	}
	b2("bypassRussia", &p.Settings.DirectRU)
	b2("adBlock", &p.Settings.BlockAds)
	b2("sniff", &p.Settings.Sniff)
	b2("allowLan", &p.Settings.AllowLAN)
	b2("autoSwitchOnFail", &p.Settings.AutoSwitch)
	b2("connectOnBoot", &p.Settings.AutoConn)
	if v, ok := st["mtu"].(float64); ok && v >= 1280 {
		p.Settings.MTU = int(v)
	}
	if v, ok := st["localProxyPort"].(float64); ok && v > 0 {
		p.Settings.ProxyPort = int(v)
	}
	if v, ok := st["pingUrl"].(string); ok && strings.HasPrefix(v, "http") {
		p.Settings.PingURL = v
	}
	if v, ok := st["theme"].(string); ok && (v == "black" || v == "dark" || v == "light") {
		p.Settings.Theme = v
	}
	return p, dropped, true
}
