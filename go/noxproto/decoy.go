package noxproto

import (
	"io"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"sync"
	"time"
)

// decoyHTML is original placeholder content. It is not a copy of any site.
// Operators should set a cover URL so unauthenticated clients see a real site
// they control; a generic page will not match a borrowed name.
const decoyHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Field notes</title>
<style>
body{font-family:Georgia,serif;max-width:40rem;margin:3rem auto;padding:0 1rem;color:#222;background:#fafaf7}
h1{font-weight:normal}
p{line-height:1.5}
</style>
</head>
<body>
<h1>Field notes</h1>
<p>Short notes on weather, routes, and whatever else is worth writing down.
Nothing here is updated on a schedule.</p>
<p>If you followed a link and expected something else, it may have moved.</p>
</body>
</html>
`

func serveDecoy(w http.ResponseWriter, r *http.Request, cover string) {
	if r.URL.Path == "/robots.txt" {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = io.WriteString(w, "User-agent: *\nDisallow:\n")
		return
	}
	if r.URL.Path == "/favicon.ico" {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if cover != "" {
		if proxyCover(w, r, cover) {
			return
		}
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, decoyHTML)
}

func proxyCover(w http.ResponseWriter, r *http.Request, cover string) bool {
	u, err := url.Parse(cover)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return false
	}
	rp := httputil.NewSingleHostReverseProxy(u)
	rp.FlushInterval = 100 * time.Millisecond
	rp.Transport = &http.Transport{ResponseHeaderTimeout: 8 * time.Second, TLSHandshakeTimeout: 8 * time.Second}
	rp.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, _ error) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, decoyHTML)
	}
	rp.Director = func(req *http.Request) {
		req.URL.Scheme = u.Scheme
		req.URL.Host = u.Host
		req.Host = u.Host
		req.Header.Del("Cookie")
		req.Header.Del("Authorization")
	}
	rp.ServeHTTP(w, r)
	return true
}

func contentTypeFor(profile string) string {
	if normalizeProfile(profile) == ProfileVideo {
		return "video/mp4"
	}
	return "application/json"
}

func pathMatch(want, got string) bool {
	want = strings.TrimRight(want, "/")
	got = strings.TrimRight(got, "/")
	if want == "" {
		want = "/api/v1/events"
	}
	return got == want
}

// flushWriter pushes each chunk out so the peer is not stuck waiting for a buffer.
// Close makes later writes fail. net/http panics if Flush runs after the
// handler returns, so Write also recovers: a tunnel tearing down must not
// crash the process.
type flushWriter struct {
	mu     sync.Mutex
	w      io.Writer
	f      http.Flusher
	closed bool
}

func (f *flushWriter) Write(p []byte) (n int, err error) {
	defer func() {
		if recover() != nil {
			n, err = 0, io.ErrClosedPipe
		}
	}()
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.closed {
		return 0, io.ErrClosedPipe
	}
	n, err = f.w.Write(p)
	if err == nil && f.f != nil {
		f.f.Flush()
	}
	return n, err
}

func (f *flushWriter) Close() {
	f.mu.Lock()
	f.closed = true
	f.mu.Unlock()
}
