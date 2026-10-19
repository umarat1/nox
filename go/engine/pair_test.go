package engine

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"nox/core"
)

func pairApp(t *testing.T) *App {
	d := t.TempDir()
	t.Setenv("LOCALAPPDATA", d)
	return NewApp(d, d)
}

func srv(name, typ, host string, port int, sub string) core.Server {
	o, _ := json.Marshal(map[string]any{"type": typ, "tag": name, "server": host, "server_port": port})
	return core.Server{ID: newID(), SubID: sub, Name: name, Type: typ, Host: host, Port: port, Outbound: o, Ping: 120}
}

func phoneApp(t *testing.T) *App {
	a := pairApp(t)
	a.p.Subs = []Sub{{ID: "s1", URL: "http://127.0.0.1:1/sub/AAA", Name: "Моя подписка", Expire: 0},
		{ID: "s2", URL: "http://127.0.0.1:1/sub/BBB", Name: "Вторая"}}
	a.p.Servers = []core.Server{srv("Лондон", "vless", "1.1.1.1", 443, "s1"), srv("США", "trojan", "2.2.2.2", 443, "s1"),
		srv("Берлин", "vless", "3.3.3.3", 443, "s2"), srv("Свой", "shadowsocks", "4.4.4.4", 8388, "")}
	a.p.Selected = a.p.Servers[1].ID
	a.p.Settings.DNS = "adguard"
	a.p.Settings.ProxyPort = 3333
	return a
}

func local(i PairInfo) string { return fmt.Sprintf("127.0.0.1:%d", i.Port) }

func TestPairTokenAll(t *testing.T) {
	ph, tv := phoneApp(t), pairApp(t)
	info, err := tv.PairStart()
	if err != nil || !info.Active || len(info.Code) != 6 || len(info.Token) < 20 {
		t.Fatal(info, err)
	}
	if info.Host != "" && !strings.HasPrefix(info.URI, "nox://pair?h="+info.Host) {
		t.Fatal(info.URI)
	}
	uri := fmt.Sprintf("nox://pair?h=%s&t=%s", local(info), info.Token)
	r, err := ph.PairSend(uri, "", PairOpts{Manual: true, Selected: true, Settings: true})
	if err != nil {
		t.Fatal(err)
	}
	if r.Subs != 2 || r.Servers != 4 || !r.Selected || !r.Settings || r.Msg != "Получено: 2 подписки, 4 сервера" {
		t.Fatalf("%+v", r)
	}
	st := tv.GetState()
	if len(st.Subs) != 2 || len(st.Servers) != 4 || st.Settings.DNS != "adguard" || st.Settings.ProxyPort == 3333 {
		t.Fatalf("%+v", st)
	}
	var sel core.Server
	for _, s := range st.Servers {
		if s.ID == st.Selected {
			sel = s
		}
		if s.Ping != 0 || s.ID == "" {
			t.Fatal("ids/ping", s)
		}
	}
	if sel.Name != "США" {
		t.Fatal("selected", sel.Name)
	}
	if s := tv.PairStatus(); s.Active || s.Result == nil || s.Result.Subs != 2 {
		t.Fatalf("status %+v", s)
	}
	// one-shot: the receiver is closed after success
	time.Sleep(500 * time.Millisecond)
	if _, err := ph.PairSend(uri, "", PairOpts{Manual: true}); err == nil {
		t.Fatal("second send accepted")
	}
}

func TestPairCodeDedupSubset(t *testing.T) {
	ph, tv := phoneApp(t), pairApp(t)
	tv.p.Subs = []Sub{{ID: "x", URL: "HTTP://127.0.0.1:1/sub/AAA/", Name: "уже есть"}}
	tv.p.Servers = []core.Server{srv("Лондон", "vless", "1.1.1.1", 443, "x"), srv("Свой-тв", "shadowsocks", "4.4.4.4", 8388, "")}
	info, _ := tv.PairStart()
	r, err := ph.PairSend(local(info), info.Code, PairOpts{SubIDs: []string{"s1", "s2"}, Manual: true})
	if err != nil {
		t.Fatal(err)
	}
	if r.Subs != 1 || r.Servers != 1 || r.Dups != 2 {
		t.Fatalf("%+v", r)
	}
	if !strings.Contains(r.Msg, "1 подписка, 1 сервер") || !strings.Contains(r.Msg, "уже были: 2") {
		t.Fatal(r.Msg)
	}
	if n := len(tv.GetState().Servers); n != 3 {
		t.Fatal("servers", n)
	}
	// subset: only s2, no manual
	ph2, tv2 := phoneApp(t), pairApp(t)
	info, _ = tv2.PairStart()
	r, err = ph2.PairSend(local(info), info.Code, PairOpts{SubIDs: []string{"s2"}})
	if err != nil || r.Subs != 1 || r.Servers != 1 || tv2.GetState().Subs[0].Name != "Вторая" {
		t.Fatalf("%+v %v", r, err)
	}
	if tv2.GetState().Selected == "" {
		t.Fatal("nothing selected after import")
	}
}

func TestPairRejects(t *testing.T) {
	ph, tv := phoneApp(t), pairApp(t)
	info, _ := tv.PairStart()
	bad := "000000"
	if bad == info.Code {
		bad = "111111"
	}
	if _, err := ph.PairSend(local(info), bad, PairOpts{}); err == nil || !strings.Contains(err.Error(), "Неверный код") {
		t.Fatal(err)
	}
	if _, err := ph.PairSend(fmt.Sprintf("nox://pair?h=%s&t=%s", local(info), b64.EncodeToString(make([]byte, 16))), "", PairOpts{}); err == nil || !strings.Contains(err.Error(), "устарел") {
		t.Fatal(err)
	}
	if n := len(tv.GetState().Subs); n != 0 {
		t.Fatal("imported with bad secret")
	}
	if _, err := ph.PairSend(local(info), "12a", PairOpts{}); err == nil || !strings.Contains(err.Error(), "6-значный") {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		ph.PairSend(local(info), bad, PairOpts{})
	}
	time.Sleep(500 * time.Millisecond)
	if s := tv.PairStatus(); s.Active || !strings.Contains(s.Error, "неверных попыток") {
		t.Fatalf("%+v", s)
	}
	// the correct code no longer works after lock-out
	if _, err := ph.PairSend(local(info), info.Code, PairOpts{}); err == nil {
		t.Fatal("accepted after lock-out")
	}
}

func TestPairUnreachable(t *testing.T) {
	ph := phoneApp(t)
	_, err := ph.PairSend("127.0.0.1:1", "123456", PairOpts{})
	if err == nil || !strings.Contains(err.Error(), "одной Wi‑Fi") {
		t.Fatal(err)
	}
	for _, s := range []string{"8.8.8.8:80", "hello", "nox://pair?h=bad"} {
		if _, _, err := ParsePairTarget(s); err == nil {
			t.Fatal("accepted", s)
		}
	}
	if hp, tok, err := ParsePairTarget(" 192.168.1.20 41234 "); err != nil || hp != "192.168.1.20:41234" || tok != "" {
		t.Fatal(hp, tok, err)
	}
	empty := pairApp(t)
	if _, err := empty.PairSend("127.0.0.1:1", "123456", PairOpts{Manual: true}); err == nil || !strings.Contains(err.Error(), "Нечего") {
		t.Fatal(err)
	}
}

func TestLanHostsHook(t *testing.T) {
	LanAddrs = func() []string { return []string{"172.19.0.1/30", "10.0.0.5/24", "fe80::1", "192.168.1.7/24", "100.64.0.1"} }
	defer func() { LanAddrs = nil }()
	h := lanHosts()
	if len(h) != 2 || h[0] != "192.168.1.7" || h[1] != "10.0.0.5" {
		t.Fatal(h)
	}
}
