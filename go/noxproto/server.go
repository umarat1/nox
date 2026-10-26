package noxproto

import (
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"encoding/binary"
	"io"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/flynn/noise"
	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
	"golang.org/x/net/http2"
)

// ServerConfig is the operator-facing configuration of a nox-protocol listener.
type ServerConfig struct {
	Identity Identity
	Path     string
	Profile  string
	Cover    string // optional URL of a site to reverse-proxy for unauthenticated clients
	Jitter   time.Duration
	// Hold is how long a CDN (batch) response waits for downstream bytes.
	Hold time.Duration
}

func (c ServerConfig) path() string {
	if c.Path == "" {
		return "/api/v1/events"
	}
	return c.Path
}

// Server accepts tunnel clients and answers everyone else like a small website.
type Server struct {
	cfg    ServerConfig
	replay *replayCache
	http   *http.Server
	h3     *http3.Server
	tcpLn  net.Listener
	udp    *net.UDPConn
	stop   chan struct{}

	mu        sync.Mutex
	cdn       map[string]*cdnSession
	seen      string
	closeOnce sync.Once
}

type cdnSession struct {
	up, down *bufPipe
	last     time.Time
}

// Listen starts TLS (HTTP/2 and HTTP/1.1) on tcpAddr and, when udpAddr is not
// empty, HTTP/3 on that UDP address. Addresses are "host:port".
func Listen(tcpAddr, udpAddr string, cert tls.Certificate, cfg ServerConfig) (*Server, error) {
	if cfg.Path == "" {
		cfg.Path = "/api/v1/events"
	}
	if cfg.Hold <= 0 {
		cfg.Hold = 200 * time.Millisecond
	}
	cfg.Profile = normalizeProfile(cfg.Profile)
	s := &Server{
		cfg:    cfg,
		replay: newReplay(),
		cdn:    map[string]*cdnSession{},
		stop:   make(chan struct{}),
	}
	h := http.HandlerFunc(s.serveHTTP)

	tlsTCP := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS13,
		NextProtos:   []string{"h2", "http/1.1"},
	}
	ln, err := net.Listen("tcp", tcpAddr)
	if err != nil {
		return nil, err
	}
	s.tcpLn = ln
	hs := &http.Server{
		Handler:           h,
		TLSConfig:         tlsTCP,
		ReadHeaderTimeout: 10 * time.Second,
	}
	if err := http2.ConfigureServer(hs, &http2.Server{
		MaxConcurrentStreams:         128,
		MaxDecoderHeaderTableSize:    4096,
		MaxUploadBufferPerConnection: 1 << 20,
		MaxUploadBufferPerStream:     256 << 10,
	}); err != nil {
		ln.Close()
		return nil, err
	}
	s.http = hs
	go hs.Serve(tls.NewListener(ln, tlsTCP))

	if udpAddr != "" {
		ua, err := net.ResolveUDPAddr("udp", udpAddr)
		if err != nil {
			s.Close()
			return nil, err
		}
		uc, err := net.ListenUDP("udp", ua)
		if err != nil {
			s.Close()
			return nil, err
		}
		s.udp = uc
		tlsUDP := tlsTCP.Clone()
		tlsUDP.NextProtos = []string{http3.NextProtoH3}
		h3s := &http3.Server{
			TLSConfig: tlsUDP,
			Handler:   h,
			QUICConfig: &quic.Config{
				MaxIdleTimeout:                 90 * time.Second,
				HandshakeIdleTimeout:           8 * time.Second,
				KeepAlivePeriod:                20 * time.Second,
				InitialStreamReceiveWindow:     6291456,
				InitialConnectionReceiveWindow: 15728640,
			},
		}
		s.h3 = h3s
		go h3s.Serve(uc)
	}
	go s.sweepCDN()
	return s, nil
}

// Addr is the TCP address actually bound.
func (s *Server) Addr() string {
	if s.tcpLn == nil {
		return ""
	}
	return s.tcpLn.Addr().String()
}

// UDPAddr is the bound HTTP/3 address, or empty when HTTP/3 is off.
func (s *Server) UDPAddr() string {
	if s.udp == nil {
		return ""
	}
	return s.udp.LocalAddr().String()
}

// SeenHost is the Host header of the latest tunnel attempt.
func (s *Server) SeenHost() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.seen
}

func (s *Server) Close() error {
	s.closeOnce.Do(func() { close(s.stop) })
	if s.h3 != nil {
		_ = s.h3.Close()
	}
	if s.udp != nil {
		_ = s.udp.Close()
	}
	if s.http != nil {
		_ = s.http.Close()
	}
	if s.tcpLn != nil {
		_ = s.tcpLn.Close()
	}
	return nil
}

func (s *Server) serveHTTP(w http.ResponseWriter, r *http.Request) {
	if !pathMatch(s.cfg.path(), r.URL.Path) || r.Method != http.MethodPost {
		serveDecoy(w, r, s.cfg.Cover)
		return
	}
	s.mu.Lock()
	s.seen = r.Host
	s.mu.Unlock()
	if r.URL.Query().Get("b") == "1" {
		s.serveBatch(w, r)
		return
	}
	msg1, err := cookieRaw(r, "sid")
	if err != nil {
		serveDecoy(w, r, s.cfg.Cover)
		return
	}
	msg2, send, recv, err := serverAccept(s.cfg.Identity, msg1, time.Now(), s.replay)
	if err != nil {
		serveDecoy(w, r, s.cfg.Cover)
		return
	}
	s.serveStream(w, r, msg2, send, recv)
}

func (s *Server) serveStream(w http.ResponseWriter, r *http.Request, msg2 []byte, send, recv *noise.CipherState) {
	fl, _ := w.(http.Flusher)
	hdr(w, s.cfg.Profile)
	w.WriteHeader(http.StatusOK)
	if fl != nil {
		fl.Flush()
	}
	var prefix [2]byte
	binary.BigEndian.PutUint16(prefix[:], uint16(len(msg2)))
	fw := &flushWriter{w: w, f: fl}
	if _, err := fw.Write(prefix[:]); err != nil {
		return
	}
	if _, err := fw.Write(msg2); err != nil {
		return
	}
	fc := newFrameConn(rw{r: r.Body, w: fw}, send, recv, s.cfg.Profile, s.cfg.Jitter)
	sess := newSession(fc, true)
	<-sess.done
	fw.Close()
}

func (s *Server) serveBatch(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie("nx"); err == nil && c.Value != "" {
		s.mu.Lock()
		sess := s.cdn[c.Value]
		if sess != nil {
			sess.last = time.Now()
		}
		s.mu.Unlock()
		if sess != nil {
			_, _ = io.Copy(sess.up, r.Body)
			writeBlob(w, s.cfg.Profile, sess.down.take(32*1024, s.cfg.Hold))
			return
		}
	}
	msg1, err := cookieRaw(r, "sid")
	if err != nil {
		serveDecoy(w, r, s.cfg.Cover)
		return
	}
	msg2, send, recv, err := serverAccept(s.cfg.Identity, msg1, time.Now(), s.replay)
	if err != nil {
		serveDecoy(w, r, s.cfg.Cover)
		return
	}
	up, down := newBufPipe(256*1024), newBufPipe(256*1024)
	cs := &cdnSession{up: up, down: down, last: time.Now()}
	id := randomID()
	s.mu.Lock()
	s.cdn[id] = cs
	s.mu.Unlock()
	go func() {
		fc := newFrameConn(rw{r: up, w: down}, send, recv, s.cfg.Profile, s.cfg.Jitter)
		sess := newSession(fc, true)
		<-sess.done
		up.Close()
		down.Close()
		s.mu.Lock()
		delete(s.cdn, id)
		s.mu.Unlock()
	}()
	_, _ = io.Copy(up, r.Body)
	http.SetCookie(w, &http.Cookie{Name: "nx", Value: id, Path: s.cfg.path(), HttpOnly: true})
	writeBlob(w, s.cfg.Profile, sessPrefix(msg2, down.take(32*1024, s.cfg.Hold)))
}

func (s *Server) sweepCDN() {
	t := time.NewTicker(30 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-s.stop:
			return
		case <-t.C:
			s.mu.Lock()
			for id, cs := range s.cdn {
				if time.Since(cs.last) > 2*time.Minute {
					cs.up.Close()
					cs.down.Close()
					delete(s.cdn, id)
				}
			}
			s.mu.Unlock()
		}
	}
}

func cookieRaw(r *http.Request, name string) ([]byte, error) {
	c, err := r.Cookie(name)
	if err != nil {
		return nil, err
	}
	return base64.RawURLEncoding.DecodeString(c.Value)
}

func hdr(w http.ResponseWriter, profile string) {
	w.Header().Set("Content-Type", contentTypeFor(profile))
	w.Header().Set("Cache-Control", "no-store, no-transform")
}

func writeBlob(w http.ResponseWriter, profile string, b []byte) {
	hdr(w, profile)
	w.WriteHeader(http.StatusOK)
	if len(b) > 0 {
		_, _ = w.Write(b)
	}
}

func sessPrefix(msg2, rest []byte) []byte {
	out := make([]byte, 2+len(msg2)+len(rest))
	binary.BigEndian.PutUint16(out[:2], uint16(len(msg2)))
	copy(out[2:], msg2)
	copy(out[2+len(msg2):], rest)
	return out
}

func randomID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	return base64.RawURLEncoding.EncodeToString(b[:])
}

type rw struct {
	r io.Reader
	w io.Writer
}

func (x rw) Read(p []byte) (int, error)  { return x.r.Read(p) }
func (x rw) Write(p []byte) (int, error) { return x.w.Write(p) }
