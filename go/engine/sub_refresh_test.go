package engine

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"nox/core"
)

const subOld = "vless://11111111-2222-3333-4444-555555555555@9.9.9.9:443?security=tls#Old1\n" +
	"vless://11111111-2222-3333-4444-555555555555@8.8.8.8:443?security=tls#Old2\n"
const subNew = "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?security=tls#New\n"

// noxUA reports a subscription User-Agent that is not the NOX/2.0 agent.
// Happ and v2rayNG impersonation makes the panel strip NOX-only protocols.
func badSubUA(ua string) string {
	if !strings.Contains(ua, "NOX/"+Version) {
		return "missing NOX/" + Version
	}
	low := strings.ToLower(ua)
	for _, bad := range []string{"happ", "v2rayng", "v2rayn"} {
		if strings.Contains(low, bad) {
			return "impersonates " + bad
		}
	}
	return ""
}

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
		// A Happ or v2rayNG body is the filtered list. Only the NOX agent is acceptable.
		if badSubUA(ua) != "" {
			_, _ = w.Write([]byte(subOld))
			return
		}
		_, _ = w.Write([]byte(subNew))
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

func TestFetchFailureKeepsServers(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "down", 500)
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.p.Subs = []Sub{{ID: "s1", URL: srv.URL, Name: "Panel"}}
	a.p.Servers = []core.Server{{ID: "keep", SubID: "s1", Name: "Keep", Type: "VLESS", Host: "9.9.9.9", Port: 443}}
	a.save()
	a.mu.Unlock()
	msg := a.RefreshSub("s1")
	if !strings.Contains(msg, "Ошибка обновления") || strings.Contains(msg, "http://") {
		t.Fatal(msg)
	}
	st := a.GetState()
	if len(st.Servers) != 1 || st.Servers[0].Name != "Keep" || st.Servers[0].Host != "9.9.9.9" {
		t.Fatalf("list wiped: %+v", st.Servers)
	}
}

func TestProfileUpdateURLIsStored(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if why := badSubUA(r.Header.Get("User-Agent")); why != "" {
			http.Error(w, why, 404)
			return
		}
		w.Header().Set("subscription-userinfo", "upload=0; download=0; total=1; expire=0")
		w.Header().Set("profile-update-url", "https://rus2.example/api/sub/new")
		_, _ = w.Write([]byte(subNew))
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.p.Subs = []Sub{{ID: "s1", URL: srv.URL, Name: "Panel"}}
	a.p.Servers = []core.Server{{ID: "old", SubID: "s1", Name: "Old", Type: "VLESS", Host: "9.9.9.9", Port: 443}}
	a.save()
	a.mu.Unlock()
	if _, _, err := a.fetchSub(&a.p.Subs[0], false); err != nil {
		t.Fatal(err)
	}
	st := a.GetState()
	if st.Subs[0].URL != "https://rus2.example/api/sub/new" {
		t.Fatalf("url %q", st.Subs[0].URL)
	}
	if len(st.Servers) != 1 || st.Servers[0].Name != "New" {
		t.Fatalf("servers %+v", st.Servers)
	}
}

func TestFetchSubSkipsHTML(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if why := badSubUA(r.Header.Get("User-Agent")); why != "" {
			http.Error(w, why, 404)
			return
		}
		w.Header().Set("Content-Type", "text/html")
		_, _ = w.Write([]byte("<html><body>vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?security=tls#New</body></html>"))
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.p.Subs = []Sub{{ID: "s1", URL: srv.URL}}
	a.p.Servers = []core.Server{{ID: "old", SubID: "s1", Name: "Keep", Type: "VLESS", Host: "9.9.9.9", Port: 443}}
	a.save()
	a.mu.Unlock()
	if _, _, err := a.fetchSub(&a.p.Subs[0], false); err == nil {
		t.Fatal("html body accepted")
	}
	st := a.GetState()
	if len(st.Servers) != 1 || st.Servers[0].Name != "Keep" || st.Servers[0].Host != "9.9.9.9" {
		t.Fatalf("%+v", st.Servers)
	}
}

func TestFlattenWrappedSubURL(t *testing.T) {
	got := flattenImport("https://panel.example/\nAbCdEf")
	if got != "https://panel.example/AbCdEf" {
		t.Fatal(got)
	}
	links := "vless://11111111-2222-3333-4444-555555555555@1.1.1.1:443#A\nvless://11111111-2222-3333-4444-555555555555@2.2.2.2:443#B"
	if flattenImport(links) != strings.TrimSpace(links) {
		t.Fatal(flattenImport(links))
	}
}

func TestImportWrappedURLAndExisting(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if why := badSubUA(r.Header.Get("User-Agent")); why != "" {
			http.Error(w, why, 404)
			return
		}
		w.Header().Set("subscription-userinfo", "upload=0; download=0; total=1; expire=0")
		w.Header().Set("profile-title", "Panel")
		_, _ = w.Write([]byte(subNew))
	}))
	defer srv.Close()
	raw := srv.URL + "/sub"
	i := strings.LastIndex(raw, "/")
	wrapped := raw[:i+1] + "\n" + raw[i+1:]
	a := NewApp(t.TempDir(), t.TempDir())
	r := a.Import(wrapped)
	if !r.OK || r.Added != 1 {
		t.Fatalf("%+v", r)
	}
	if len(a.GetState().Subs) != 1 || a.GetState().Subs[0].URL != raw {
		t.Fatalf("url %q", a.GetState().Subs[0].URL)
	}
	again := a.Import(raw + "/")
	if !again.OK || !strings.Contains(again.Msg, "уже есть") {
		t.Fatalf("%+v", again)
	}
	if len(a.GetState().Subs) != 1 {
		t.Fatalf("dup %+v", a.GetState().Subs)
	}
}

func TestProfileWebPageDoesNotReplaceURL(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if why := badSubUA(r.Header.Get("User-Agent")); why != "" {
			http.Error(w, why, 404)
			return
		}
		w.Header().Set("subscription-userinfo", "upload=0; download=0; total=1; expire=0")
		w.Header().Set("profile-web-page-url", "https://panel.example/page")
		w.Header().Set("profile-title", "base64:UGFuZWw")
		_, _ = w.Write([]byte(subNew))
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	r := a.Import(srv.URL)
	if !r.OK {
		t.Fatal(r)
	}
	st := a.GetState()
	if st.Subs[0].URL != srv.URL {
		t.Fatalf("url replaced: %s", st.Subs[0].URL)
	}
	if len(st.Servers) != 1 || st.Servers[0].Name != "New" {
		t.Fatalf("%+v", st.Servers)
	}
}

func TestImportNoServersIsNotOK(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		_, _ = w.Write([]byte("not a subscription"))
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	r := a.Import(srv.URL)
	if r.OK || len(a.GetState().Subs) != 0 || r.Msg == "" {
		t.Fatalf("%+v subs %d", r, len(a.GetState().Subs))
	}
}

func TestFetchSubReturnsBeforeDescFetch(t *testing.T) {
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ua := r.Header.Get("User-Agent")
		if why := badSubUA(ua); why != "" {
			http.Error(w, why, 500)
			return
		}
		// Description fetch has no cache-buster. It must not block the list refresh,
		// and it must use the same NOX agent (not Happ).
		if r.URL.Query().Get("nocache") == "" {
			<-release
			http.NotFound(w, r)
			return
		}
		w.Header().Set("subscription-userinfo", "upload=0; download=0; total=1; expire=0")
		_, _ = w.Write([]byte(subNew))
	}))
	defer srv.Close()
	defer close(release)
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.p.Subs = []Sub{{ID: "s1", URL: srv.URL, Name: "Panel"}}
	a.save()
	a.mu.Unlock()
	done := make(chan string, 1)
	go func() { done <- a.RefreshSub("s1") }()
	select {
	case msg := <-done:
		if strings.Contains(msg, "Ошибка") {
			t.Fatal(msg)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("refresh blocked on the description request")
	}
}

func TestSubUserAgentContainsNoxVersion(t *testing.T) {
	ua := subUserAgent()
	if ua != "NOX/"+Version+" "+deviceOS() {
		t.Fatal(ua)
	}
	if why := badSubUA(ua); why != "" {
		t.Fatal(why, ua)
	}
}

func TestFetchDescsUsesNoxAgent(t *testing.T) {
	var ua string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ua = r.Header.Get("User-Agent")
		_, _ = w.Write([]byte("vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?security=tls#New?serverDescription=aGk\n"))
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	m := a.fetchDescs(srv.URL)
	if why := badSubUA(ua); why != "" {
		t.Fatal(why, ua)
	}
	if m["New"] != "hi" {
		t.Fatalf("ua %q descs %+v", ua, m)
	}
}

func TestEverySubRequestUsesNoxAgent(t *testing.T) {
	var mu sync.Mutex
	var uas []string
	desc := make(chan struct{}, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		uas = append(uas, r.Header.Get("User-Agent"))
		mu.Unlock()
		if r.URL.Query().Get("nocache") == "" {
			select {
			case desc <- struct{}{}:
			default:
			}
			_, _ = w.Write([]byte("vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?security=tls#New?serverDescription=aGk\n"))
			return
		}
		w.Header().Set("subscription-userinfo", "upload=0; download=0; total=1; expire=0")
		_, _ = w.Write([]byte(subNew))
	}))
	defer srv.Close()
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.p.Subs = []Sub{{ID: "s1", URL: srv.URL, Name: "Panel"}}
	a.save()
	a.mu.Unlock()
	if _, _, err := a.fetchSub(&a.p.Subs[0], false); err != nil {
		t.Fatal(err)
	}
	select {
	case <-desc:
	case <-time.After(2 * time.Second):
		t.Fatal("description request was not sent")
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		st := a.GetState()
		if len(st.Servers) == 1 && st.Servers[0].Desc == "hi" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("description not applied: %+v", st.Servers)
		}
		time.Sleep(15 * time.Millisecond)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(uas) < 2 {
		t.Fatalf("requests %v", uas)
	}
	for _, ua := range uas {
		if why := badSubUA(ua); why != "" {
			t.Fatalf("%s: %q in %v", why, ua, uas)
		}
	}
}
