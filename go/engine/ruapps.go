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
	// 2.3.1: UI group (Банки, Госуслуги, Маркетплейсы, Яндекс, VK, Связь, Транспорт, Кино, Другое)
	Group string `json:"group,omitempty"`
}

var ruApps = []RuApp{
	// banks / payments
	{"ru.sberbankmobile", "СберБанк", false, "Банки"}, {"com.idamob.tinkoff.android", "Т-Банк", false, "Банки"},
	{"ru.vtb24.mobilebanking.android", "ВТБ", false, "Банки"}, {"ru.alfabank.mobile.android", "Альфа-Банк", false, "Банки"},
	{"ru.gazprombank.android.mobilebank.app", "Газпромбанк", false, "Банки"}, {"ru.raiffeisennews", "Райффайзен Банк", false, "Банки"},
	{"ru.letobank.Prometheus", "Почта Банк", false, "Банки"}, {"com.openbank", "Открытие / БМ-Банк", false, "Банки"},
	{"ru.mts.bank", "МТС Банк", false, "Банки"}, {"ru.simpls.mbrd.ui", "МТС Банк (старое)", false, "Банки"}, {"ru.lewis.dbo", "МТС Деньги", false, "Банки"},
	{"ru.ozon.fintech.finance", "Ozon Банк", false, "Банки"}, {"ru.sovcombank.dbo", "Совкомбанк", false, "Банки"},
	{"ru.rshb.dbo", "Россельхозбанк", false, "Банки"}, {"ru.nspk.mirpay", "Mir Pay", false, "Банки"}, {"ru.nspk.sbpay", "СБПэй", false, "Банки"},
	// government
	{"ru.rostel", "Госуслуги", false, "Госуслуги"}, {"ru.gosuslugi.goskey", "Госключ", false, "Госуслуги"}, {"ru.gosuslugi.pos", "Госуслуги.Решаем вместе", false, "Госуслуги"},
	{"ru.fns.lkfl", "Налоги ФЛ", false, "Госуслуги"}, {"ru.altarix.mos.pgu", "Моя Москва (mos.ru)", false, "Госуслуги"}, {"ru.mos.app", "Моя Москва", false, "Госуслуги"},
	{"ru.emias.app", "ЕМИАС", false, "Госуслуги"},
	// marketplaces / services
	{"ru.ozon.app.android", "Ozon", false, "Маркетплейсы"}, {"com.wildberries.ru", "Wildberries", false, "Маркетплейсы"}, {"com.avito.android", "Авито", false, "Маркетплейсы"},
	{"ru.instamart", "Купер (СберМаркет)", false, "Маркетплейсы"}, {"ru.dodopizza.app", "Додо Пицца", false, "Маркетплейсы"}, {"com.deliveryclub", "Delivery Club", false, "Маркетплейсы"},
	{"ru.sbcs.store", "Самокат", false, "Маркетплейсы"}, {"ru.rzd.pass", "РЖД Пассажирам", false, "Транспорт"}, {"ru.dublgis.dgismobile", "2ГИС", false, "Транспорт"},
	{"ru.beru.android", "Яндекс Маркет", false, "Яндекс"}, {"com.yandex.lavka", "Яндекс Лавка", false, "Яндекс"},
	{"ru.gazprom.mobile", "Газпром", false, "Другое"},
	// social / mail / messengers / stores
	{"com.vkontakte.android", "ВКонтакте", false, "VK"}, {"com.vk.im", "VK Мессенджер", false, "VK"}, {"ru.oneme.app", "MAX", false, "VK"},
	{"ru.mail.mailapp", "Почта Mail.ru", false, "VK"}, {"ru.mail.cloud", "Облако Mail.ru", false, "VK"}, {"ru.vk.store", "RuStore", false, "VK"},
	{"ru.ok.android", "Одноклассники", false, "VK"},
	// operators
	{"ru.mts.mymts", "Мой МТС", false, "Связь"}, {"ru.beeline.services", "Билайн", false, "Связь"}, {"ru.megafon.mlk", "МегаФон", false, "Связь"},
	{"ru.tele2.mytele2", "t2 (Tele2)", false, "Связь"},
	// video / TV (phone and Android TV)
	{"ru.kinopoisk", "Кинопоиск", true, "Яндекс"}, {"ru.kinopoisk.tv", "Кинопоиск (ТВ)", true, "Яндекс"}, {"ru.more.play", "Okko", true, "Кино"},
	{"ru.rt.video.app.mobile", "Wink", true, "Кино"}, {"ru.rt.video.app.tv", "Wink (ТВ)", true, "Кино"}, {"ru.ivi.client", "Иви", true, "Кино"},
	{"gpm.tnt_premier", "PREMIER", true, "Кино"}, {"ru.start.androidmobile", "START", true, "Кино"}, {"com.vk.vkvideo", "VK Видео", true, "Кино"},
	{"com.vk.tv", "VK Видео (ТВ)", true, "Кино"}, {"ru.rutube.app", "RUTUBE", true, "Кино"}, {"com.vgtrk.smotrim", "Смотрим", true, "Кино"},
	{"ru.mts.mtstv", "KION", true, "Кино"}, {"com.megogo.application", "MEGOGO", true, "Кино"}, {"com.infolink.limeiptv", "Лайм HD TV", true, "Кино"},
	{"ru.cn.tv", "Peers.TV", true, "Кино"},
	{"com.kms.free", "Kaspersky", false, "Другое"},
	// 2.3.1 additions, each id checked on RuStore (rustore.ru/catalog/app/<id>) or Google Play on 2026-11-03
	{"ru.ftc.faktura.sovkombank", "Совкомбанк", false, "Банки"}, {"logo.com.mbanking", "ПСБ", false, "Банки"},
	{"ru.bankuralsib.mb.android", "Уралсиб", false, "Банки"}, {"ru.yoo.money", "ЮMoney", false, "Банки"},
	{"com.octopod.russianpost.client.android", "Почта России", false, "Госуслуги"},
	{"ru.pyaterochka.app.browser", "Пятёрочка", false, "Маркетплейсы"}, {"ru.perekrestok.app", "Перекрёсток", false, "Маркетплейсы"},
	{"ru.tander.magnit", "Магнит", false, "Маркетплейсы"},
	{"ru.foodfox.client", "Яндекс Еда", false, "Яндекс"},
	{"com.uma.musicvk", "VK Музыка", false, "VK"},
	{"com.dartit.RTcabinet", "Мой Ростелеком", false, "Связь"},
	{"ru.aeroflot", "Аэрофлот", false, "Транспорт"}, {"ru.mosmetro.metro", "Метро Москвы (Тройка)", false, "Транспорт"},
}

// ruAppPrefixes: every installed app under these ids (Яндекс Go, Карты, Музыка, Браузер, Алиса, Яндекс ТВ…).
var ruAppPrefixes = []string{"ru.yandex.", "com.yandex."}

// RuApps: the curated list (UI marks these «RU»); prefixes end with "*".
func (a *App) RuApps() []RuApp {
	out := append([]RuApp(nil), ruApps...)
	for _, p := range ruAppPrefixes {
		out = append(out, RuApp{Pkg: p + "*", Label: "Яндекс (все приложения)", TV: true, Group: "Яндекс"})
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

// effectiveSplitExtra (2.3.1): as effectiveSplit plus user-added packages («Добавить своё» in the
// «мимо VPN» list); they bypass the VPN whenever the Russian list is on.
func effectiveSplitExtra(mode string, apps []string, ru bool, off, extra []string) (string, []string) {
	m, l := effectiveSplit(mode, apps, ru, off)
	if !ru || mode == "include" || len(extra) == 0 {
		return m, l
	}
	seen := map[string]bool{}
	for _, p := range l {
		seen[p] = true
	}
	for _, p := range extra {
		if p = strings.TrimSpace(p); p != "" && !seen[p] {
			seen[p] = true
			l = append(l, p)
		}
	}
	return m, l
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
