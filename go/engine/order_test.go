package engine

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"nox/core"
)

func ids(l []core.Server) string {
	s := ""
	for _, x := range l {
		s += x.ID
	}
	return s
}

func TestReorderSlots(t *testing.T) {
	l := []core.Server{{ID: "a"}, {ID: "b"}, {ID: "c"}, {ID: "d"}, {ID: "e"}}
	if g := ids(reorderSlots(l, []string{"d", "b"})); g != "adcbe" {
		t.Fatal(g)
	}
	if g := ids(reorderSlots(l, []string{"e", "a", "c"})); g != "ebadc" {
		t.Fatal(g)
	}
}

func TestSortByOld(t *testing.T) {
	l := []core.Server{{Name: "x"}, {Name: "new"}, {Name: "y"}, {Name: "z"}}
	sortByOld(l, map[string]int{"z": 1, "x": 5, "y": 3})
	if l[0].Name != "z" || l[1].Name != "y" || l[2].Name != "x" || l[3].Name != "new" {
		t.Fatal(l)
	}
}

func newTestApp(t *testing.T) *App {
	os.Setenv("LOCALAPPDATA", t.TempDir())
	return NewApp("", "")
}

func TestDeleteDeadUndo(t *testing.T) {
	a := newTestApp(t)
	a.p.Servers = []core.Server{{ID: "a", Ping: 50}, {ID: "b", Ping: -1}, {ID: "c", Ping: -1, Type: core.BalancerLabel}, {ID: "d", Ping: -1}, {ID: "e"}}
	a.p.Selected = "b"
	if n := a.DeleteDead(nil); n != 2 {
		t.Fatal(n)
	}
	if ids(a.p.Servers) != "ace" || a.p.Selected != "a" {
		t.Fatal(ids(a.p.Servers))
	}
	a.UndoDelete()
	if ids(a.p.Servers) != "abcde" {
		t.Fatal(ids(a.p.Servers))
	}
}

func TestReorderSubs(t *testing.T) {
	a := newTestApp(t)
	a.p.Subs = []Sub{{ID: "1"}, {ID: "2"}, {ID: "3"}}
	a.ReorderSubs([]string{"3", "1", "2"})
	if a.p.Subs[0].ID != "3" || a.p.Subs[2].ID != "2" {
		t.Fatal(a.p.Subs)
	}
}

func TestUpdateCheckAndHide(t *testing.T) {
	ok := true
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !ok {
			w.WriteHeader(500)
			return
		}
		w.Write([]byte(`{"versionName":"0.7.28","nox2-linux":{"versionName":"9.0.0","url":"https://x/y"}}`))
	}))
	defer srv.Close()
	old := UpdateURL
	UpdateURL = srv.URL
	defer func() { UpdateURL = old }()
	oldFB := UpdateFallbackURLs
	UpdateFallbackURLs = nil
	defer func() { UpdateFallbackURLs = oldFB }()
	a := newTestApp(t)
	ok = false
	if _, good := a.checkUpdate(); good || a.p.UpdOK != 0 {
		t.Fatal("failure must not set throttle timestamp")
	}
	ok = true
	u, good := a.checkUpdate()
	if !good || u == nil || u.Version != "9.0.0" || a.p.UpdOK == 0 {
		t.Fatal(u, good)
	}
	if a.GetState().Update == nil {
		t.Fatal("should be visible")
	}
	a.HideUpdate("9.0.0")
	if a.GetState().Update != nil {
		t.Fatal("hidden for 24h")
	}
	nowFn = func() time.Time { return time.Now().Add(25 * time.Hour) }
	defer func() { nowFn = time.Now }()
	if a.GetState().Update == nil {
		t.Fatal("visible again after 24h")
	}
}

func TestDropOpenVPN(t *testing.T) {
	d := t.TempDir()
	a := NewApp(d, d)
	ok := a.ImportLegacy(`{"servers":[{"id":"1","name":"OVPN","type":"OpenVPN UDP","outbound":{"type":"_openvpn"}},{"id":"2","name":"S","type":"SSTP","outbound":{"type":"_sstp"}}]}`)
	if !ok || len(a.GetState().Servers) != 1 || a.GetState().Servers[0].ID != "2" {
		t.Fatal(ok, a.GetState().Servers)
	}
}
