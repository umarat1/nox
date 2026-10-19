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
	if m, l = effectiveSplit("", nil, false, nil); m != "" || l != nil {
		t.Fatal(m, l)
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
