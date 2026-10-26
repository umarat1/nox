package engine

import "strings"

// ivi packages always bypass the VPN, even when «российские приложения» is off.
// The prefix is expanded to every installed ru.ivi.* app (phone, TV, lite).
var iviPkgs = []string{"ru.ivi.client", "ru.ivi.client.tv", "ru.ivi.androidtv", "ru.ivi.lite"}

// RuApp: a Russian app that, when installed, bypasses the VPN on Android (as 0.7.22+ RuApps).
// Package ids from the 0.7.69 list, checked against Google Play / RuStore (several banks are
// RuStore-only now, their ids are unchanged). TV apps included (Android TV parity).
type RuApp struct {
	Pkg   string `json:"pkg"`
	Label string `json:"label"`
	TV    bool   `json:"tv,omitempty"`
}

var ruApps = []RuApp{
	// banks / payments
	{"ru.sberbankmobile", "СберБанк", false}, {"com.idamob.tinkoff.android", "Т-Банк", false},
	{"ru.vtb24.mobilebanking.android", "ВТБ", false}, {"ru.alfabank.mobile.android", "Альфа-Банк", false},
	{"ru.gazprombank.android.mobilebank.app", "Газпромбанк", false}, {"ru.raiffeisennews", "Райффайзен Банк", false},
	{"ru.letobank.Prometheus", "Почта Банк", false}, {"com.openbank", "Открытие / БМ-Банк", false},
	{"ru.mts.bank", "МТС Банк", false}, {"ru.simpls.mbrd.ui", "МТС Банк (старое)", false}, {"ru.lewis.dbo", "МТС Деньги", false},
	{"ru.ozon.fintech.finance", "Ozon Банк", false}, {"ru.sovcombank.dbo", "Совкомбанк", false},
	{"ru.rshb.dbo", "Россельхозбанк", false}, {"ru.nspk.mirpay", "Mir Pay", false}, {"ru.nspk.sbpay", "СБПэй", false},
	// government
	{"ru.rostel", "Госуслуги", false}, {"ru.gosuslugi.goskey", "Госключ", false}, {"ru.gosuslugi.pos", "Госуслуги.Решаем вместе", false},
	{"ru.fns.lkfl", "Налоги ФЛ", false}, {"ru.altarix.mos.pgu", "Моя Москва (mos.ru)", false}, {"ru.mos.app", "Моя Москва", false},
	{"ru.emias.app", "ЕМИАС", false},
	// marketplaces / services
	{"ru.ozon.app.android", "Ozon", false}, {"com.wildberries.ru", "Wildberries", false}, {"com.avito.android", "Авито", false},
	{"ru.instamart", "Купер (СберМаркет)", false}, {"ru.dodopizza.app", "Додо Пицца", false}, {"com.deliveryclub", "Delivery Club", false},
	{"ru.sbcs.store", "Самокат", false}, {"ru.rzd.pass", "РЖД Пассажирам", false}, {"ru.dublgis.dgismobile", "2ГИС", false},
	{"ru.beru.android", "Яндекс Маркет", false}, {"com.yandex.lavka", "Яндекс Лавка", false},
	{"ru.gazprom.mobile", "Газпром", false},
	// social / mail / messengers / stores
	{"com.vkontakte.android", "ВКонтакте", false}, {"com.vk.im", "VK Мессенджер", false}, {"ru.oneme.app", "MAX", false},
	{"ru.mail.mailapp", "Почта Mail.ru", false}, {"ru.mail.cloud", "Облако Mail.ru", false}, {"ru.vk.store", "RuStore", false},
	{"ru.ok.android", "Одноклассники", false},
	// operators
	{"ru.mts.mymts", "Мой МТС", false}, {"ru.beeline.services", "Билайн", false}, {"ru.megafon.mlk", "МегаФон", false},
	{"ru.tele2.mytele2", "t2 (Tele2)", false},
	// video / TV (phone and Android TV)
	{"ru.kinopoisk", "Кинопоиск", true}, {"ru.kinopoisk.tv", "Кинопоиск (ТВ)", true}, {"ru.more.play", "Okko", true},
	{"ru.rt.video.app.mobile", "Wink", true}, {"ru.rt.video.app.tv", "Wink (ТВ)", true}, {"ru.ivi.client", "Иви", true},
	{"gpm.tnt_premier", "PREMIER", true}, {"ru.start.androidmobile", "START", true}, {"com.vk.vkvideo", "VK Видео", true},
	{"com.vk.tv", "VK Видео (ТВ)", true}, {"ru.rutube.app", "RUTUBE", true}, {"com.vgtrk.smotrim", "Смотрим", true},
	{"ru.mts.mtstv", "KION", true}, {"com.megogo.application", "MEGOGO", true}, {"com.infolink.limeiptv", "Лайм HD TV", true},
	{"ru.cn.tv", "Peers.TV", true},
	{"com.kms.free", "Kaspersky", false},
}

// ruAppPrefixes: every installed app under these ids (Яндекс Go, Карты, Музыка, Браузер, Алиса, Яндекс ТВ…).
var ruAppPrefixes = []string{"ru.yandex.", "com.yandex."}

// RuApps: the curated list (UI marks these «RU»); prefixes end with "*".
func (a *App) RuApps() []RuApp {
	out := append([]RuApp(nil), ruApps...)
	for _, p := range ruAppPrefixes {
		out = append(out, RuApp{Pkg: p + "*", Label: "Яндекс (все приложения)", TV: true})
	}
	return out
}

func isRuApp(pkg string) bool {
	for _, p := range ruAppPrefixes {
		if strings.HasPrefix(pkg, p) {
			return true
		}
	}
	for _, r := range ruApps {
		if r.Pkg == pkg {
			return true
		}
	}
	return false
}

// effectiveSplit: user split + Russian apps. RU apps apply in «all apps» and «all except
// selected» modes (in «only selected» they are simply not in the VPN anyway). Prefix entries
// ("ru.yandex.*") are expanded to installed packages by the Android service.
func iviPkg(p string) bool {
	if p == "ru.ivi.*" || strings.HasPrefix(strings.TrimSuffix(p, "*"), "ru.ivi.") {
		return true
	}
	return false
}

// withIviBypass forces the ivi app outside the VPN.
// include-mode: drop ivi from the allow-list (its traffic never enters the tunnel).
// If that would leave the allow-list empty, switch to exclude so the rest of the
// device stays in the VPN and only ivi is outside.
func withIviBypass(mode string, apps []string) (string, []string) {
	if mode == "include" {
		var keep []string
		for _, p := range apps {
			if !iviPkg(p) {
				keep = append(keep, p)
			}
		}
		if len(keep) == 0 {
			return "exclude", iviExcludeList()
		}
		return "include", keep
	}
	seen := map[string]bool{}
	var out []string
	add := func(p string) {
		if p != "" && !seen[p] {
			seen[p] = true
			out = append(out, p)
		}
	}
	for _, p := range apps {
		add(p)
	}
	for _, p := range iviExcludeList() {
		add(p)
	}
	return "exclude", out
}

func iviExcludeList() []string {
	out := append([]string{}, iviPkgs...)
	return append(out, "ru.ivi.*")
}

func effectiveSplit(mode string, apps []string, ru bool, off []string) (string, []string) {
	if !ru || mode == "include" {
		return withIviBypass(mode, apps)
	}
	skip := map[string]bool{}
	for _, p := range off {
		skip[p] = true
	}
	seen := map[string]bool{}
	var out []string
	add := func(p string) {
		if p != "" && !seen[p] {
			seen[p] = true
			out = append(out, p)
		}
	}
	if mode == "exclude" {
		for _, p := range apps {
			add(p)
		}
	}
	for _, r := range ruApps {
		if !skip[r.Pkg] {
			add(r.Pkg)
		}
	}
	for _, p := range ruAppPrefixes {
		if !skip[p+"*"] {
			add(p + "*")
		}
	}
	return withIviBypass("exclude", out)
}
