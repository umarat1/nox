package engine

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestEffectiveSplit(t *testing.T) {
	m, l := effectiveSplit("", nil, true, []string{"ru.kinopoisk"})
	if m != "exclude" || !slices.Contains(l, "ru.sberbankmobile") || !slices.Contains(l, "ru.yandex.*") || slices.Contains(l, "ru.kinopoisk") || !slices.Contains(l, "com.vk.tv") {
		t.Fatal(m, l)
	}
	m, l = effectiveSplit("exclude", []string{"org.my.app"}, true, nil)
	if m != "exclude" || l[0] != "org.my.app" || !slices.Contains(l, "ru.rostel") {
		t.Fatal(m, l)
	}
	if m, l = effectiveSplit("include", []string{"org.telegram"}, true, nil); m != "include" || len(l) != 1 {
		t.Fatal(m, l)
	}
	if m, l = effectiveSplit("", nil, false, nil); m != "exclude" || !slices.Contains(l, "ru.ivi.client") || !slices.Contains(l, "ru.ivi.*") {
		t.Fatal(m, l)
	}
	if m, l = effectiveSplit("include", []string{"ru.ivi.client", "org.telegram"}, false, nil); m != "include" || len(l) != 1 || l[0] != "org.telegram" {
		t.Fatal("ivi must leave the include list", m, l)
	}
	if m, l = effectiveSplit("include", []string{"ru.ivi.client"}, false, nil); m != "exclude" || !slices.Contains(l, "ru.ivi.client") {
		t.Fatal("include-only-ivi", m, l)
	}
}

func TestRuAppsMigration(t *testing.T) {
	cases := map[string]bool{
		`{"setVer":25,"settings":{"mode":"tun"}}`:                                                 true,
		`{"setVer":25,"settings":{"splitMode":"include","splitApps":["org.telegram"]}}`:           false,
		`{"setVer":25,"settings":{"splitMode":"exclude","splitApps":["org.telegram.messenger"]}}`: false,
		`{"setVer":110,"settings":{"ruApps":false}}`:                                              false,
	}
	for js, want := range cases {
		d := t.TempDir()
		os.WriteFile(filepath.Join(d, "state.json"), []byte(js), 0o600)
		a := NewApp(d, d)
		if a.p.Settings.RuApps != want {
			t.Fatal(js, a.p.Settings.RuApps)
		}
	}
	if a := NewApp(t.TempDir(), ""); !a.p.Settings.RuApps || !a.p.Settings.DirectRU {
		t.Fatal("fresh install defaults")
	}
}

func TestRuAppsGroupsAndExtra(t *testing.T) {
	groups := map[string]bool{"Банки": true, "Госуслуги": true, "Маркетплейсы": true, "Яндекс": true, "VK": true, "Связь": true, "Транспорт": true, "Кино": true, "Другое": true}
	seen := map[string]bool{}
	for _, r := range ruApps {
		if !groups[r.Group] || seen[r.Pkg] {
			t.Fatal("bad group or duplicate", r)
		}
		seen[r.Pkg] = true
	}
	m, l := effectiveSplitExtra("", nil, true, nil, []string{"org.example.bank", " "})
	if m != "exclude" || !slices.Contains(l, "org.example.bank") || !slices.Contains(l, "ru.yoo.money") {
		t.Fatal(m, l)
	}
	if _, l = effectiveSplitExtra("", nil, false, nil, []string{"org.example.bank"}); slices.Contains(l, "org.example.bank") {
		t.Fatal("extra must follow the RU toggle")
	}
}
