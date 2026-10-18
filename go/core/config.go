package core

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }

type Settings struct {
	Mode      string `json:"mode"` // "tun" | "proxy"
	DNS       string `json:"dns"`  // cloudflare|google|yandex|adguard|custom
	CustomDNS string `json:"customDns"`
	DirectRU  bool   `json:"directRu"`
	BlockAds  bool   `json:"blockAds"`
	IPv6      bool   `json:"ipv6"`
	ProxyPort int    `json:"proxyPort"`
	AllowLAN  bool   `json:"allowLan"`
	AutoConn  bool   `json:"autoConnect"`
	Autostart bool   `json:"autostart"`
	PingMode  string `json:"pingMode"` // url|tcp
	MTU       int    `json:"mtu"`
	Sniff     bool   `json:"sniff"`
	LogLevel  string `json:"logLevel"`
	Theme     string `json:"theme"` // black|dark|light (as on Android)
	// 0.8.1
	AutoSwitch bool   `json:"autoSwitch"` // switch server when the current one stops passing traffic
	PingURL    string `json:"pingUrl"`    // check point for «через прокси» ping ("" = gstatic)
	// 1.0: UI-only preferences (category chip, view, hideDead, dedup, …) kept by the core
	UI map[string]string `json:"ui,omitempty"`
	// Android per-app split tunnelling: "" (all apps) | "include" (only SplitApps) | "exclude" (all but SplitApps)
	SplitMode string   `json:"splitMode,omitempty"`
	SplitApps []string `json:"splitApps,omitempty"`
}

func DefaultSettings() Settings {
	return Settings{Mode: "tun", DNS: "cloudflare", DirectRU: true, IPv6: false, ProxyPort: 2080, PingMode: "url", MTU: 9000, Sniff: true, LogLevel: "warn"}
}

func dnsServer(s Settings) map[string]any {
	switch s.DNS {
	case "google":
		return map[string]any{"type": "https", "server": "8.8.8.8"}
	case "yandex":
		return map[string]any{"type": "udp", "server": "77.88.8.8"}
	case "adguard":
		return map[string]any{"type": "https", "server": "94.140.14.14"}
	case "quad9":
		return map[string]any{"type": "https", "server": "9.9.9.9"}
	case "custom":
		c := strings.TrimSpace(s.CustomDNS)
		switch {
		case strings.HasPrefix(c, "https://"):
			h := strings.TrimPrefix(c, "https://")
			path := "/dns-query"
			if i := strings.Index(h, "/"); i >= 0 {
				path = h[i:]
				h = h[:i]
			}
			return map[string]any{"type": "https", "server": h, "path": path, "domain_resolver": "local"}
		case strings.HasPrefix(c, "tls://"):
			return map[string]any{"type": "tls", "server": strings.TrimPrefix(c, "tls://"), "domain_resolver": "local"}
		case c != "":
			return map[string]any{"type": "udp", "server": strings.TrimPrefix(c, "udp://")}
		}
	}
	return map[string]any{"type": "https", "server": "1.1.1.1"}
}

var RuSuffixes = []string{"ru", "su", "xn--p1ai", "xn--d1acj3b", "xn--80asehdb", "xn--c1avg", "xn--80aswg", "moscow", "xn--80adxhks",
	"gov.ru", "yandex.net", "yandex.com", "yastatic.net", "yandex.cloud", "ya.ru", "dzen.ru", "vk.com", "vk.me", "vk.ru", "vkuser.net", "userapi.com", "vk-cdn.net",
	"mail.ru", "mycdn.me", "ok.ru", "max.ru", "gosuslugi.ru", "sberbank.com", "tinkoff.ru", "tbank.ru", "ozon.ru", "wildberries.ru", "wb.ru", "avito.st", "kaspersky.com", "1c.ru"}

// BuildConfig builds a sing-box 1.14 config. proxy is the outbound/endpoint JSON (already resolved for qWDTT).
func BuildConfig(proxy map[string]any, s Settings, clashAddr string, ruleDir string) ([]byte, error) {
	proxy["tag"] = "proxy"
	isEndpoint := proxy["type"] == "wireguard"
	var extraOuts []any
	if proxy["type"] == BalancerType {
		arr, _ := proxy["outbounds"].([]any)
		var tags []string
		for i, x := range arr {
			if m, ok := x.(map[string]any); ok {
				t := fmt.Sprintf("m%d", i)
				m["tag"] = t
				tags = append(tags, t)
				extraOuts = append(extraOuts, m)
			}
		}
		if len(tags) == 0 {
			return nil, fmt.Errorf("автовыбор: нет серверов")
		}
		u := map[string]any{"type": "urltest", "tag": "proxy", "outbounds": tags, "url": proxy["url"], "interval": proxy["interval"], "tolerance": proxy["tolerance"]}
		proxy = u
	}
	ruSets := false
	if s.DirectRU && ruleDir != "" {
		if _, err := os.Stat(filepath.Join(ruleDir, "geoip-ru.srs")); err == nil {
			ruSets = true
		}
	}
	listen := "127.0.0.1"
	if s.AllowLAN {
		listen = "0.0.0.0"
	}
	port := s.ProxyPort
	if port == 0 {
		port = 2080
	}
	var inbounds []any
	mixed := map[string]any{"type": "mixed", "tag": "mixed-in", "listen": listen, "listen_port": port}
	if s.Mode == "proxy" {
		// system proxy is set by the app (cleared reliably on disconnect)
	}
	inbounds = append(inbounds, mixed)
	if s.Mode != "proxy" {
		addr := []string{"172.19.0.1/30"}
		if s.IPv6 {
			addr = append(addr, "fdfe:dcba:9876::1/126")
		}
		mtu := s.MTU
		if mtu == 0 {
			mtu = 9000
		}
		inbounds = append(inbounds, map[string]any{"type": "tun", "tag": "tun-in", "interface_name": "Nox", "address": addr,
			"mtu": mtu, "auto_route": true, "strict_route": true, "stack": "mixed"})
	}
	ds := dnsServer(s)
	ds["tag"] = "remote"
	ds["detour"] = "proxy"
	servers := []any{ds, map[string]any{"type": "local", "tag": "local"}}
	dnsRules := []any{}
	if s.DirectRU {
		dnsRules = append(dnsRules, map[string]any{"domain_suffix": RuSuffixes, "server": "local"})
		if ruSets {
			dnsRules = append(dnsRules, map[string]any{"rule_set": "geosite-ru", "server": "local"})
		}
	}
	strategy := "ipv4_only"
	if s.IPv6 {
		strategy = "prefer_ipv4"
	}
	rules := []any{}
	if s.Sniff {
		rules = append(rules, map[string]any{"action": "sniff"})
	}
	rules = append(rules,
		map[string]any{"protocol": "dns", "action": "hijack-dns"},
		map[string]any{"ip_is_private": true, "outbound": "direct"},
	)
	procs := []string{"sing-box.exe", "qwdtt.exe", "xray.exe", "sing-box", "qwdtt", "xray"}
	rules = append(rules, map[string]any{"process_name": procs, "outbound": "direct"})
	if s.BlockAds {
		rules = append(rules, map[string]any{"rule_set": "ads", "action": "reject"})
	}
	if s.DirectRU {
		rules = append(rules, map[string]any{"domain_suffix": RuSuffixes, "outbound": "direct"})
		if ruSets {
			rules = append(rules, map[string]any{"rule_set": []string{"geosite-ru", "geoip-ru"}, "outbound": "direct"})
		}
	}
	if !s.IPv6 {
		rules = append(rules, map[string]any{"ip_version": 6, "action": "reject"})
	}
	route := map[string]any{"rules": rules, "final": "proxy", "auto_detect_interface": true, "default_domain_resolver": "local"}
	var sets []any
	if s.BlockAds {
		if p := filepath.Join(ruleDir, "geosite-category-ads-all.srs"); ruleDir != "" && fileExists(p) {
			sets = append(sets, map[string]any{"type": "local", "tag": "ads", "format": "binary", "path": p})
		} else {
			sets = append(sets, map[string]any{"type": "remote", "tag": "ads", "format": "binary",
				"url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs", "download_detour": "proxy"})
		}
	}
	if ruSets {
		sets = append(sets, map[string]any{"type": "local", "tag": "geosite-ru", "format": "binary", "path": filepath.Join(ruleDir, "geosite-category-ru.srs")},
			map[string]any{"type": "local", "tag": "geoip-ru", "format": "binary", "path": filepath.Join(ruleDir, "geoip-ru.srs")})
	}
	if len(sets) > 0 {
		route["rule_set"] = sets
	}
	lvl := s.LogLevel
	if lvl == "" {
		lvl = "warn"
	}
	cfg := map[string]any{
		"log":       map[string]any{"level": lvl, "timestamp": true},
		"dns":       map[string]any{"servers": servers, "rules": dnsRules, "final": "remote", "strategy": strategy},
		"inbounds":  inbounds,
		"outbounds": []any{map[string]any{"type": "direct", "tag": "direct"}},
		"route":     route,
		"experimental": map[string]any{"clash_api": map[string]any{"external_controller": clashAddr},
			"cache_file": map[string]any{"enabled": false}},
	}
	if isEndpoint {
		cfg["endpoints"] = []any{proxy}
	} else {
		cfg["outbounds"] = append(append([]any{proxy}, extraOuts...), map[string]any{"type": "direct", "tag": "direct"})
	}
	return json.MarshalIndent(cfg, "", "  ")
}

// TestConfig: minimal config exposing the server through a local mixed port (used for URL ping).
func TestConfig(proxy map[string]any, port int) ([]byte, error) {
	proxy["tag"] = "proxy"
	cfg := map[string]any{
		"log":      map[string]any{"level": "error"},
		"inbounds": []any{map[string]any{"type": "mixed", "listen": "127.0.0.1", "listen_port": port}},
		"route":    map[string]any{"final": "proxy", "default_domain_resolver": "local"},
		"dns":      map[string]any{"servers": []any{map[string]any{"type": "local", "tag": "local"}}},
	}
	if proxy["type"] == "wireguard" {
		cfg["endpoints"] = []any{proxy}
		cfg["outbounds"] = []any{map[string]any{"type": "direct", "tag": "direct"}}
	} else {
		cfg["outbounds"] = []any{proxy}
	}
	return json.Marshal(cfg)
}
