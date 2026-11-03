package core

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
)

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }

// withKV copies m and sets k=v.
func withKV(m map[string]any, k string, v any) map[string]any {
	o := map[string]any{k: v}
	for a, b := range m {
		o[a] = b
	}
	return o
}

type Settings struct {
	Mode      string `json:"mode"` // "tun" | "proxy"
	DNS       string `json:"dns"`  // auto|cloudflare|google|quad9|adguard|yandex|dnsai|comss|xbox|controld|mullvad|nextdns|custom
	CustomDNS string `json:"customDns"`
	DirectRU  bool   `json:"directRu"`
	BlockAds  bool   `json:"blockAds"`
	// 2.3.1: «Блокировка рекламы» sub-toggles (apply only while BlockAds is on).
	AdsGoogle     bool `json:"adsGoogle"`     // Google ad networks (AdSense/AdMob/DoubleClick)
	AdsYandex     bool `json:"adsYandex"`     // Yandex Direct/AdFox/РСЯ + Метрика counters
	AdsMailVK     bool `json:"adsMailVk"`     // Mail.ru / VK / myTarget ad + counter hosts
	AdsOther      bool `json:"adsOther"`      // rest of geosite category-ads-all (filtered)
	AdsAnalytics  bool `json:"adsAnalytics"`  // optional: Google Analytics / Firebase Analytics / GTM
	AdsAppMetrica bool `json:"adsAppMetrica"` // optional: Yandex AppMetrica (may break some RU apps)
	// 2.4.0: Rutube ad/stat hosts (AdGuard DNS filter, RU AdList, AdGuard Russian filter).
	AdsRutube bool `json:"adsRutube"`
	// 2.4.0 «Не блокировать»: domain suffixes exempt from every ad rule (DNS and route).
	AdsAllow   []string `json:"adsAllow,omitempty"`
	IPv6       bool     `json:"ipv6"`
	ProxyPort  int      `json:"proxyPort"`
	AllowLAN   bool     `json:"allowLan"`
	NoSysProxy bool     `json:"noSysProxy"` // proxy mode: do not set the Windows system proxy
	AutoConn   bool     `json:"autoConnect"`
	Autostart  bool     `json:"autostart"`
	PingMode   string   `json:"pingMode"` // url|tcp
	MTU        int      `json:"mtu"`
	Sniff      bool     `json:"sniff"`
	LogLevel   string   `json:"logLevel"`
	Theme      string   `json:"theme"` // black|dark|light (as on Android)
	// 0.8.1
	AutoSwitch bool   `json:"autoSwitch"` // switch server when the current one stops passing traffic
	PingURL    string `json:"pingUrl"`    // check point for «через прокси» ping ("" = gstatic)
	// 1.0: UI-only preferences (category chip, view, hideDead, dedup, …) kept by the core
	UI map[string]string `json:"ui,omitempty"`
	// Android per-app split tunnelling: "" (all apps) | "include" (only SplitApps) | "exclude" (all but SplitApps)
	SplitMode string   `json:"splitMode,omitempty"`
	SplitApps []string `json:"splitApps,omitempty"`
	// 1.0.10 (as 0.7.22+): installed Russian apps (engine.RuApps) bypass the VPN on Android;
	// RuAppsOff are the ones the user switched back into the VPN.
	RuApps    bool     `json:"ruApps"`
	RuAppsOff []string `json:"ruAppsOff,omitempty"`
	// 2.3.1: user-added packages for the «мимо VPN» list (edited in the grouped list UI)
	RuAppsExtra []string `json:"ruAppsExtra,omitempty"`
	// Custom routing: domain suffixes always direct / always through the VPN (wins over RU rules).
	DirectDomains []string `json:"directDomains,omitempty"`
	// 1.0.20 «Раздача VPN»: login/password for the LAN proxy (AllowLAN); empty = no auth
	ShareUser    string   `json:"shareUser,omitempty"`
	SharePass    string   `json:"sharePass,omitempty"`
	ProxyDomains []string `json:"proxyDomains,omitempty"`
	// 1.0.28: after a ping, select the lowest-latency server (while disconnected).
	AutoBest bool `json:"autoBest"`
	// TCP Fast Open (2.3.3: no implicit multiplex — Xray servers do not speak sing-box smux).
	FastDial bool `json:"fastDial"`
	// 2.1: «МТС прокси» — all servers via the operator HTTP proxy 192.168.192.192:80
	MtsProxy bool `json:"mtsProxy"`
	// 2.3.2 «Автоскачивание обновлений» (Android): "always" (Wi‑Fi and mobile data; also
	// when empty, so upgrading users get it) | "wifi" (unmetered only) | "off".
	AutoDl string `json:"autoDl,omitempty"`
}

// ShareSources: client addresses allowed on the LAN proxy (AllowLAN): RFC 1918 + loopback.
var ShareSources = []string{"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "::1/128"}

func DefaultSettings() Settings {
	return Settings{Mode: "tun", DNS: "auto", DirectRU: true, RuApps: true, IPv6: false, ProxyPort: 10808, PingMode: "url", MTU: 9000, Sniff: true, LogLevel: "warn", AutoBest: true, FastDial: true,
		AdsGoogle: true, AdsYandex: true, AdsMailVK: true, AdsOther: true, AdsRutube: true,
		// 2.3.2: fresh installs start with ad blocking (all vendors, incl. the optional ones),
		// auto-connect and start-with-system on; IPv6 stays off.
		BlockAds: true, AdsAnalytics: true, AdsAppMetrica: true, AutoConn: true, Autostart: true, AutoDl: "always"}
}

// IviSuffixes always go direct (the site and its own CDN), even when «российские сайты» is off.
// ivi.ru covers api/dfs/rocket/player subdomains. ivicdn.tv and tivision.ru are the player CDN
// (ASN IVI); video segments are served from *.dfs.ivi.ru.
var IviSuffixes = []string{"ivi.ru", "ivi.tv", "ivicdn.tv", "tivision.ru"}

// 2.2.1 note: Google/YouTube ad hosts are blocked by name even if the ads rule set fails to
// load. They are separate from the hosts that
// serve video (youtube.com, googlevideo.com, ytimg.com, ggpht.com), which are never blocked:
// YouTube's in-stream ads come from those same hosts, so they cannot be told apart by domain.
// 2.3.1 ad lists, taken from geosite category-ads-all (v2fly domain-list-community via
// SagerNet/sing-geosite) and split by vendor so each one has its own toggle. Deliberately NOT
// blocked because they break the services themselves: clck.yandex.ru (Yandex search result
// redirects), r.mail.ru (links in Mail.ru letters/news), metrika.yandex.* / appmetrica.yandex.ru
// dashboards, ms.vk.com, startup.mobile.yandex.net, mtalk.google.com, *.googleapis.com.
var AdsGoogleSuffixes = []string{"doubleclick.net", "googlesyndication.com", "googleadservices.com",
	"adservice.google.com", "ads.youtube.com", "pagead.l.google.com", "partnerad.l.google.com", "googletagservices.com",
	"2mdn.net", "admob.com"}

// adservice.google.ru / .de / .com.tr …
var AdsGoogleRegex = []string{`^adservice\.google\.([a-z]{2,3}|com?\.[a-z]{2})$`}

var AdsAnalyticsSuffixes = []string{"google-analytics.com", "app-measurement.com", "googletagmanager.com"}

var AdsYandexSuffixes = []string{"an.yandex.ru", "yabs.yandex.ru", "bs.yandex.ru", "adfox.ru", "adfox.yandex.ru",
	"ads.yandex.ru", "ads.yandex", "adv.yandex.ru", "adv.yandex.com", "adfstat.yandex.ru", "awaps.yandex.net",
	"yandexadexchange.net", "mc.yandex.ru", "mc.yandex.com", "counter.yandex.ru", "yandex-metrica.ru"}

var AdsAppMetricaSuffixes = []string{"appmetrica.yandex.net", "appmetrica.yandex.com", "yandexmetrica.com"}

var AdsMailVKSuffixes = []string{"ad.mail.ru", "alt-ad.mail.ru", "rs.mail.ru", "top-fwz1.mail.ru", "relap.mail.ru",
	"radar.imgsmail.ru", "target.my.com", "tracker.my.com", "tracker-api.my.com", "ads.vk.com", "adv.vk.com",
	"target.vk.ru", "vk-analytics.ru", "analytics.vk.com"}

// AdsRutubeSuffixes (2.4.0). Hosts listed by at least two of the public filter lists that
// work on whole hosts, checked 2026-11:
//   - a.rutube.ru, ssp.rutube.ru: AdGuard DNS filter, AdGuard Russian filter, RU AdList
//     (ad server and Rutube's own SSP);
//   - log.rutube.ru: AdGuard DNS filter and HaGeZi Pro (statistics beacon).
//
// Rutube also loads ads from paths on its main host (rutube.ru/api/advert/,
// ac.rutube.ru/api/*/banner_rules). A DNS or domain rule cannot block those without
// breaking the site, so they are not listed here. Players embedded on other sites
// (mediavitrina, Yandex adsdk) are covered by the Yandex toggle and «Прочие сети».
var AdsRutubeSuffixes = []string{"a.rutube.ru", "ssp.rutube.ru", "log.rutube.ru"}

// AdSuffixesFor: every hand-listed host the current toggles block.
func AdSuffixesFor(s Settings) []string {
	var out []string
	for _, r := range AdRules(s, false) {
		if v, ok := r.Match["domain_suffix"].([]string); ok {
			out = append(out, v...)
		}
	}
	return out
}

// AdRule is one vendor's ad matcher. Each vendor gets its own rule, so the index of the
// DNS rule that answered NXDOMAIN tells which source was blocked (see AdSources).
type AdRule struct {
	Src   string         // google|analytics|yandex|appmetrica|mailvk|rutube|other
	Match map[string]any // domain_suffix / domain_regex / rule_set
}

// AdRules: one matcher per enabled vendor, in a fixed order (BlockAds itself is checked by
// the caller).
func AdRules(s Settings, haveOther bool) []AdRule {
	var out []AdRule
	if s.AdsGoogle {
		out = append(out, AdRule{"google", map[string]any{"domain_suffix": AdsGoogleSuffixes, "domain_regex": AdsGoogleRegex}})
	}
	if s.AdsAnalytics {
		out = append(out, AdRule{"analytics", map[string]any{"domain_suffix": AdsAnalyticsSuffixes}})
	}
	if s.AdsYandex {
		out = append(out, AdRule{"yandex", map[string]any{"domain_suffix": AdsYandexSuffixes}})
	}
	if s.AdsAppMetrica {
		out = append(out, AdRule{"appmetrica", map[string]any{"domain_suffix": AdsAppMetricaSuffixes}})
	}
	if s.AdsMailVK {
		out = append(out, AdRule{"mailvk", map[string]any{"domain_suffix": AdsMailVKSuffixes}})
	}
	if s.AdsRutube {
		out = append(out, AdRule{"rutube", map[string]any{"domain_suffix": AdsRutubeSuffixes}})
	}
	if s.AdsOther && haveOther {
		out = append(out, AdRule{"other", map[string]any{"rule_set": "ads"}})
	}
	return out
}

// AdSources: the vendor of each leading DNS rule of BuildConfig's output (index = sing-box
// "dns: match[i]"). Empty when ad blocking is off.
func AdSources(s Settings, ruleDir string) []string {
	if !s.BlockAds {
		return nil
	}
	var out []string
	for _, r := range AdRules(s, adsOtherPath(s, ruleDir) != "") {
		out = append(out, r.Src)
	}
	return out
}

// AdSig (2.4.0): the text sing-box prints for an ad rule's matcher in its "match[i] <rule> =>"
// debug lines (DomainItem shows at most 3 suffixes; a rule set shows its tag). The engine's
// counter attributes both DNS (NXDOMAIN) and route (reject) matches by it, so the counts do
// not depend on rule indices.
func AdSig(r AdRule) string {
	if rs, ok := r.Match["rule_set"].(string); ok {
		return "rule_set=" + rs
	}
	d, _ := r.Match["domain_suffix"].([]string)
	switch {
	case len(d) == 0:
		return ""
	case len(d) == 1:
		return "domain_suffix=" + d[0]
	case len(d) > 3:
		return "domain_suffix=[" + strings.Join(d[:3], " ") + "...]"
	}
	return "domain_suffix=[" + strings.Join(d, " ") + "]"
}

// AdSigs: vendor → signature for the enabled ad rules (empty when ad blocking is off).
func AdSigs(s Settings, ruleDir string) map[string]string {
	if !s.BlockAds {
		return nil
	}
	m := map[string]string{}
	for _, r := range AdRules(s, adsOtherPath(s, ruleDir) != "") {
		if sig := AdSig(r); sig != "" {
			m[r.Src] = sig
		}
	}
	return m
}

func adsOtherPath(s Settings, ruleDir string) string {
	if s.BlockAds && s.AdsOther && ruleDir != "" {
		if p := filepath.Join(ruleDir, "geosite-ads-other.srs"); fileExists(p) {
			return p
		}
	}
	return ""
}

// adMatchers: the sing-box rule bodies for the toggles. With an allow-list, each matcher
// becomes a logical AND with an inverted allow rule, so allowed hosts fall through to the
// normal DNS / routing rules.
func adMatchers(s Settings, haveOther bool) []map[string]any {
	allow := cleanDomains(s.AdsAllow)
	var m []map[string]any
	for _, r := range AdRules(s, haveOther) {
		if len(allow) == 0 {
			m = append(m, r.Match)
			continue
		}
		m = append(m, map[string]any{"type": "logical", "mode": "and", "rules": []any{
			r.Match,
			map[string]any{"domain_suffix": allow, "invert": true},
		}})
	}
	return m
}

// IviProcesses: desktop player binaries. Android uses package exclusion (ru.ivi.*) instead.
var IviProcesses = []string{"ivi.exe", "Ivi.exe", "IVI.exe", "ivi", "Ivi"}

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
	case "dnsai", "comss", "xbox", "controld", "mullvad", "nextdns":
		// DoH by hostname (certificate checked against it); hostname resolved by the local resolver.
		h, path := map[string][2]string{
			"dnsai":    {"dns.dns-ai.ru", "/dns-query"},
			"comss":    {"dns.comss.one", "/dns-query"},
			"xbox":     {"xbox-dns.ru", "/dns-query"},
			"controld": {"freedns.controld.com", "/p0"},
			"mullvad":  {"dns.mullvad.net", "/dns-query"},
			"nextdns":  {"dns.nextdns.io", "/dns-query"},
		}[s.DNS][0], ""
		path = map[string]string{"controld": "/p0"}[s.DNS]
		if path == "" {
			path = "/dns-query"
		}
		return map[string]any{"type": "https", "server": h, "path": path, "domain_resolver": "local"}
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
		case c != "" && net.ParseIP(strings.TrimPrefix(c, "udp://")) != nil:
			return map[string]any{"type": "udp", "server": strings.TrimPrefix(c, "udp://")}
		}
	}
	return map[string]any{"type": "https", "server": "1.1.1.1"}
}

// RuSuffixes: Russian sites bypassing the VPN (0.7.24 RuSites list + 1.0 additions). sing-box
// domain_suffix is label-aware ("ru" matches *.ru, not "guru"). geosite-category-ru / geoip-ru
// rule sets (bundled) cover the rest.
var RuSuffixes = []string{
	// TLDs: .ru .su .рф .москва .дети .рус .сайт .орг .moscow
	"ru", "su", "xn--p1ai", "xn--80adxhks", "xn--d1acj3b", "xn--p1acf", "xn--80asehdb", "xn--c1avg", "xn--80aswg", "moscow", "tatar",
	// government
	"gov.ru", "gosuslugi.ru", "esia.gosuslugi.ru", "nalog.ru", "nalog.gov.ru", "mos.ru", "kremlin.ru", "government.ru",
	"sfr.gov.ru", "mvd.ru", "cbr.ru", "rosreestr.ru", "rosreestr.gov.ru", "gibdd.ru", "fssp.gov.ru", "fssprus.ru", "emias.info",
	// Yandex
	"yandex.net", "yandex.com", "yandex.by", "yandex.kz", "yandex.uz", "yandex.com.tr", "yandex.az", "yandex.com.am", "yandex.com.ge",
	"yastatic.net", "yandex.cloud", "yandexcloud.net", "yandex-team.ru", "ya.ru", "yandex.ru", "dzen.ru", "kinopoisk.ru", "kinopoisk.tv", "kp.ru",
	// VK / Mail.ru / OK / MAX
	"mail.ru", "imgsmail.ru", "mycdn.me", "ok.ru", "odnoklassniki.ru", "odkl.ru", "mradx.net", "list.ru", "bk.ru", "inbox.ru",
	"vk.com", "vk.ru", "vk.me", "vk.cc", "vk.link", "userapi.com", "vkuser.net", "vk-cdn.net", "vkuservideo.net", "vkvideo.ru", "vk-portal.net",
	"max.ru", "oneme.ru",
	// marketplaces / banks / services / TV
	"ozon.ru", "ozon.com", "ozonusercontent.com", "ozone.ru", "wildberries.ru", "wb.ru", "wbbasket.ru", "wbstatic.net",
	"sber.ru", "sberbank.ru", "sberbank.com", "sbrf.ru", "tbank.ru", "tinkoff.ru", "tcsbank.ru", "tbank-online.com",
	"avito.ru", "avito.st", "2gis.ru", "2gis.com", "2gis.io", "rutube.ru", "rutubelist.ru", "kaspersky.com", "1c.ru",
	"ivi.tv", "okko.tv", "wink.ru", "start.ru", "premier.one", "smotrim.ru", "kion.ru", "24h.tv", "limehd.tv", "peers.tv", "megogo.ru",
}

// BuildConfig builds a sing-box 1.14 config. proxy is the outbound/endpoint JSON (already resolved for qWDTT).
func BuildConfig(proxy map[string]any, s Settings, clashAddr string, ruleDir string) ([]byte, error) {
	proxy, extraOuts, err := expandChain(proxy)
	if err != nil {
		return nil, err
	}
	proxy["tag"] = "proxy"
	isEndpoint := proxy["type"] == "wireguard"
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
		if s.MtsProxy {
			var keep []string
			var outs2 []any
			for _, x := range extraOuts {
				m, _ := x.(map[string]any)
				if m != nil && MtsBlocked(m) != "" {
					continue
				}
				outs2 = append(outs2, x)
				if m != nil {
					if t, _ := m["tag"].(string); t != "" {
						keep = append(keep, t)
					}
				}
			}
			extraOuts, tags = outs2, keep
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
	// «Прочие сети»: category-ads-all with Google/Yandex/Mail.ru/VK hosts removed
	// (scripts/make-ads-other.py), so those vendors follow their own toggles.
	adsOther := adsOtherPath(s, ruleDir)
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
	if s.AllowLAN && s.ShareUser != "" {
		mixed["users"] = []any{map[string]any{"username": s.ShareUser, "password": s.SharePass}}
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
	if s.BlockAds {
		// 2.2.1: ad hosts get NXDOMAIN, so blocking holds for direct and proxied apps alike
		// and apps give up at once instead of waiting on a rejected connection.
		// 2.4.0: these must stay the first DNS rules — AdSources maps "match[i]" to a vendor.
		for _, m := range adMatchers(s, adsOther != "") {
			r := map[string]any{"action": "predefined", "rcode": "NXDOMAIN"}
			for k, v := range m {
				r[k] = v
			}
			dnsRules = append(dnsRules, r)
		}
	}
	// ivi is resolved on the direct resolver so the player does not get a tunnel address.
	dnsRules = append(dnsRules, map[string]any{"domain_suffix": IviSuffixes, "server": "local"})
	if pd := cleanDomains(s.ProxyDomains); len(pd) > 0 {
		dnsRules = append(dnsRules, map[string]any{"domain_suffix": pd, "server": "remote"})
	}
	if dd := cleanDomains(s.DirectDomains); len(dd) > 0 {
		dnsRules = append(dnsRules, map[string]any{"domain_suffix": dd, "server": "local"})
	}
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
	if s.AllowLAN {
		// 2.3.2 «Раздача через точку доступа»: the proxy listens on every interface, but only
		// hotspot / USB / home-LAN clients (RFC 1918) and the phone itself may use it.
		// 2.3.3: a logical AND rule. In 2.3.2 the whole rule {inbound, source_ip_cidr} had
		// invert=true, which sing-box applies to the entire match: everything that was NOT
		// (mixed-in AND private source) was rejected — i.e. all TUN traffic, every protocol.
		rules = append(rules, map[string]any{"type": "logical", "mode": "and", "rules": []any{
			map[string]any{"inbound": []string{"mixed-in"}},
			map[string]any{"source_ip_cidr": ShareSources, "invert": true},
		}, "action": "reject"})
	}
	if s.Sniff {
		rules = append(rules, map[string]any{"action": "sniff"})
	}
	rules = append(rules,
		map[string]any{"protocol": "dns", "action": "hijack-dns"},
		map[string]any{"ip_is_private": true, "outbound": "direct"},
	)
	procs := []string{"sing-box.exe", "qwdtt.exe", "xray.exe", "noxd.exe", "naive.exe", "sing-box", "qwdtt", "xray", "noxd", "naive"}
	rules = append(rules, map[string]any{"process_name": procs, "outbound": "direct"})
	// ivi site, CDN and desktop app — always direct, ahead of user proxy rules.
	rules = append(rules, map[string]any{"domain_suffix": IviSuffixes, "outbound": "direct"})
	rules = append(rules, map[string]any{"process_name": IviProcesses, "outbound": "direct"})
	if s.BlockAds {
		// ahead of every direct rule (user, RU, YouTube-direct subscriptions): applies to both paths
		for _, m := range adMatchers(s, adsOther != "") {
			m["action"] = "reject"
			rules = append(rules, m)
		}
	}
	if pd := cleanDomains(s.ProxyDomains); len(pd) > 0 {
		rules = append(rules, map[string]any{"domain_suffix": pd, "outbound": "proxy"})
	}
	if dd := cleanDomains(s.DirectDomains); len(dd) > 0 {
		rules = append(rules, map[string]any{"domain_suffix": dd, "outbound": "direct"})
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
	if adsOther != "" {
		sets = append(sets, map[string]any{"type": "local", "tag": "ads", "format": "binary", "path": adsOther})
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
	if s.FastDial {
		tuneOutbound(proxy)
		for _, o := range extraOuts {
			if m, ok := o.(map[string]any); ok {
				tuneOutbound(m)
			}
		}
	}
	if s.MtsProxy {
		all := []map[string]any{proxy}
		for _, o := range extraOuts {
			if m, ok := o.(map[string]any); ok {
				all = append(all, m)
			}
		}
		if err := ApplyMts(all); err != nil {
			return nil, err
		}
		extraOuts = append(extraOuts, MtsOutbound())
		// the operator proxy itself is reached directly (it is only inside the MTS network)
		rules = append([]any{map[string]any{"ip_cidr": []string{MtsProxyHost + "/32"}, "outbound": "direct"}}, rules...)
		route["rules"] = rules
	}
	if isEndpoint {
		cfg["endpoints"] = []any{proxy}
	} else {
		cfg["outbounds"] = append(append([]any{proxy}, extraOuts...), map[string]any{"type": "direct", "tag": "direct"})
	}
	return json.MarshalIndent(cfg, "", "  ")
}

// tuneOutbound lowers handshake latency where it is safe.
// TCP Fast Open falls back to a normal handshake if the server ignores it.
// Multiplex is never added (2.3.3): Xray-based servers do not speak sing-box smux.
func tuneOutbound(ob map[string]any) {
	if ob == nil {
		return
	}
	t, _ := ob["type"].(string)
	switch t {
	case "vless", "vmess", "trojan", "shadowsocks", "socks", "http":
		if _, ok := ob["tcp_fast_open"]; !ok {
			ob["tcp_fast_open"] = true
		}
	case "anytls":
		// 2.3.3: sing-box refuses to start an AnyTLS outbound with TCP Fast Open
		// ("tcp_fast_open is not supported with anytls outbound").
		delete(ob, "tcp_fast_open")
	}
	// 2.3.3: no implicit multiplex any more. sing-box smux is not understood by Xray /
	// 3x-ui / Remnawave Shadowsocks and VMess inbounds: with «быстрое подключение» on
	// (default), every SS server from an Xray panel connected but passed no traffic.
	// A link's own multiplex settings are still kept.
}

// TestConfig: minimal config exposing the server through a local mixed port (used for URL ping).
func TestConfig(proxy map[string]any, port int) ([]byte, error) {
	proxy, chainOuts, err := expandChain(proxy)
	if err != nil {
		return nil, err
	}
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
		cfg["outbounds"] = append([]any{proxy}, chainOuts...)
	}
	return json.Marshal(cfg)
}

// cleanDomains: user lists ("https://Site.ru/path", "*.example.com", ".рф") -> suffixes.
func cleanDomains(in []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, d := range in {
		d = strings.ToLower(strings.TrimSpace(d))
		if i := strings.Index(d, "://"); i >= 0 {
			d = d[i+3:]
		}
		d = strings.Trim(strings.SplitN(d, "/", 2)[0], ". *")
		if h, _, ok := strings.Cut(d, ":"); ok {
			d = h
		}
		if d == "" || strings.ContainsAny(d, " ,;") || seen[d] {
			continue
		}
		seen[d] = true
		out = append(out, toASCII(d))
	}
	return out
}
