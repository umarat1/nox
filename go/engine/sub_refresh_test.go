package engine

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"nox/core"
)

const subOld = "vless://11111111-2222-3333-4444-555555555555@9.9.9.9:443?security=tls#Old1\n" +
	"vless://11111111-2222-3333-4444-555555555555@8.8.8.8:443?security=tls#Old2\n"
const subNew = "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?security=tls#New\n"

func TestFetchSubReplacesList(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Cache-Control") == "" || r.Header.Get("x-hwid") == "" || r.URL.Query().Get("nocache") == "" {
			http.Error(w, "headers", 500)
			return
		}
		ua := r.Header.Get("User-Agent")
		w.Header().Set("subscription-userinfo", "upload=1; download=2; total=9; expire=2000000000")
		w.Header().Set("profile-update-interval", "3")
		w.Header().Set("profile-title", "Panel")
		// A Nox-specific body still carries yesterday's regions. The client must not use it
		// when a standard client already got the current list.
		if strings.HasPrefix(ua, "Nox/") {
			_, _ = w.Write([]byte(subOld))
			return
		}
		if strings.HasPrefix(ua, "v2rayNG/") {
			_, _ = w.Write([]byte(subNew))
			return
		}
		http.Error(w, "ua", 404)
	}))
	defer srv.Close()

	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.p.Subs = []Sub{{ID: "s1", URL: srv.URL, Name: "old"}}
	a.p.Servers = []core.Server{
		{ID: "a", SubID: "s1", Name: "Old1", Type: "VLESS", Host: "9.9.9.9", Port: 443},
		{ID: "b", SubID: "s1", Name: "Old2", Type: "VLESS", Host: "8.8.8.8", Port: 443},
		{ID: "m", Name: "Manual", Type: "VLESS", Host: "5.5.5.5", Port: 443},
	}
	a.p.Selected = "a"
	a.save()
	a.mu.Unlock()

	msg := a.RefreshSub("s1")
	st := a.GetState()
	if len(st.Servers) != 2 {
		t.Fatalf("servers %d msg %s %+v", len(st.Servers), msg, st.Servers)
	}
	var got []string
	for _, s := range st.Servers {
		got = append(got, s.Name+"/"+s.SubID+"/"+s.Host)
	}
	joined := strings.Join(got, ",")
	if strings.Contains(joined, "Old1") || strings.Contains(joined, "Old2") || !strings.Contains(joined, "New/s1/1.2.3.4") || !strings.Contains(joined, "Manual//5.5.5.5") {
		t.Fatal(joined, msg)
	}
	if st.Subs[0].Interval != 3 || st.Subs[0].Name != "Panel" || st.Subs[0].Total != 9 {
		t.Fatalf("sub %+v", st.Subs[0])
	}
	if st.Selected == "a" || st.Selected == "" {
		t.Fatal("selection", st.Selected)
	}
	if !strings.Contains(msg, "было 2, стало 1") {
		t.Fatal(msg)
	}
}

func TestFetchSubSkipsHTML(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.Header.Get("User-Agent"), "v2rayNG/") {
			w.Header().Set("Content-Type", "text/html")
			_, _ = w.Write([]byte("<html><body>vless://11111111-2222-3333-4444-555555555555@9.9.9.9:443?security=tls#Stale</body></html>"))
			return
		}
		if strings.HasPrefix(r.Header.Get("User-Agent"), "Happ/") {
			w.Header().Set("subscription-userinfo", "upload=0; download=0; total=0; expire=0")
			_, _ = w.Write([]byte(subNew))
			return
		}
		http.Error(w, "no", 404)
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.p.Subs = []Sub{{ID: "s1", URL: srv.URL}}
	a.p.Servers = []core.Server{{ID: "old", SubID: "s1", Name: "Stale", Type: "VLESS", Host: "9.9.9.9", Port: 443}}
	a.save()
	a.mu.Unlock()
	if _, _, err := a.fetchSub(&a.p.Subs[0], false); err != nil {
		t.Fatal(err)
	}
	st := a.GetState()
	if len(st.Servers) != 1 || st.Servers[0].Name != "New" || st.Servers[0].Host != "1.2.3.4" {
		t.Fatalf("%+v", st.Servers)
	}
}
