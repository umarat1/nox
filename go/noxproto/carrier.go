package noxproto

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
	utls "github.com/refraction-networking/utls"
	"golang.org/x/net/http2"
)

func helloID(name string) utls.ClientHelloID {
	switch strings.ToLower(name) {
	case "firefox":
		return utls.HelloFirefox_Auto
	case "safari":
		return utls.HelloSafari_Auto
	case "ios":
		return utls.HelloIOS_Auto
	case "random":
		ids := []utls.ClientHelloID{utls.HelloChrome_Auto, utls.HelloFirefox_Auto, utls.HelloSafari_Auto, utls.HelloIOS_Auto}
		return ids[int(randUint32())%len(ids)]
	default:
		return utls.HelloChrome_Auto
	}
}

func userAgent(fp string) string {
	switch strings.ToLower(fp) {
	case "firefox":
		return "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0"
	case "safari":
		return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"
	case "ios":
		return "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1"
	default:
		return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
	}
}

func dialUTLS(ctx context.Context, addr, sni, fp string, insecure bool) (*utls.UConn, error) {
	d := &net.Dialer{Timeout: 10 * time.Second}
	tcp, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, err
	}
	cfg := &utls.Config{
		ServerName:         sni,
		InsecureSkipVerify: insecure,
		NextProtos:         []string{"h2", "http/1.1"},
	}
	u := utls.UClient(tcp, cfg, helloID(fp))
	if err := u.HandshakeContext(ctx); err != nil {
		tcp.Close()
		return nil, err
	}
	return u, nil
}

// stdTLS exposes a uTLS connection as the small interface net/http2 expects.
type stdTLS struct{ *utls.UConn }

func (s stdTLS) ConnectionState() tls.ConnectionState {
	st := s.UConn.ConnectionState()
	return tls.ConnectionState{
		Version:            st.Version,
		HandshakeComplete:  st.HandshakeComplete,
		CipherSuite:        st.CipherSuite,
		NegotiatedProtocol: st.NegotiatedProtocol,
		ServerName:         st.ServerName,
	}
}

type h2link struct {
	tr   *http2.Transport
	conn net.Conn
}

func (h *h2link) Close() error {
	if h.tr != nil {
		h.tr.CloseIdleConnections()
	}
	if h.conn != nil {
		return h.conn.Close()
	}
	return nil
}

func newH2(ctx context.Context, cfg Config, addr string) (*h2link, error) {
	u, err := dialUTLS(ctx, addr, cfg.SNI, cfg.Fingerprint, cfg.Insecure)
	if err != nil {
		return nil, err
	}
	if u.ConnectionState().NegotiatedProtocol != "h2" {
		u.Close()
		return nil, errors.New("nox: сервер не выбрал HTTP/2")
	}
	var once sync.Once
	wrapped := stdTLS{u}
	tr := &http2.Transport{
		DisableCompression:        true,
		MaxDecoderHeaderTableSize: 65536,
		MaxEncoderHeaderTableSize: 65536,
		MaxHeaderListSize:         262144,
		MaxReadFrameSize:          16384,
		DialTLSContext: func(context.Context, string, string, *tls.Config) (net.Conn, error) {
			var c net.Conn
			once.Do(func() { c = wrapped })
			if c == nil {
				return nil, errors.New("nox: HTTP/2 соединение уже использовано")
			}
			return c, nil
		},
	}
	return &h2link{tr: tr, conn: u}, nil
}

func authCookie(msg []byte) string {
	return "sid=" + base64.RawURLEncoding.EncodeToString(msg)
}

func decorate(req *http.Request, cfg Config, cookie string) {
	req.Header.Set("User-Agent", userAgent(cfg.Fingerprint))
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("Content-Type", contentTypeFor(cfg.Profile))
	req.Header.Set("Cookie", cookie)
}

type tunnel struct {
	raw io.ReadWriteCloser
	fc  *frameConn
	ses *session
	cl  func()
}

func (t *tunnel) Close() error {
	if t.cl != nil {
		t.cl()
	}
	if t.raw != nil {
		return t.raw.Close()
	}
	return nil
}

// dialCarrier opens one post-handshake multiplexed session.
func dialCarrier(ctx context.Context, cfg Config, carrier string) (*session, func(), error) {
	switch carrier {
	case CarrierH2:
		return dialStream(ctx, cfg, cfg.Addr, false)
	case CarrierFront:
		addr := cfg.Addr
		if cfg.Front != "" {
			if _, _, err := net.SplitHostPort(cfg.Front); err != nil {
				addr = net.JoinHostPort(cfg.Front, "443")
			} else {
				addr = cfg.Front
			}
		}
		return dialStream(ctx, cfg, addr, false)
	case CarrierH3:
		addr := cfg.Addr
		if cfg.H3Addr != "" {
			addr = cfg.H3Addr
		}
		return dialStream(ctx, cfg, addr, true)
	case CarrierCDN:
		return dialCDN(ctx, cfg)
	default:
		return nil, nil, errors.New("nox: неизвестный канал " + carrier)
	}
}

func dialStream(ctx context.Context, cfg Config, addr string, h3 bool) (*session, func(), error) {
	id := Identity{Password: cfg.Password}
	msg1, hs, err := clientHello(id, cfg.Pub, time.Now())
	if err != nil {
		return nil, nil, err
	}
	// SOCKS cancels the dial context the moment Dial returns. The multiplexed
	// POST has to keep living after that, so the request uses its own context.
	// ctx still aborts the handshake itself.
	life, lifeCancel := context.WithCancel(context.Background())
	pr, pw := io.Pipe()
	reqURL := "https://" + cfg.authority() + cfg.path()
	req, err := http.NewRequestWithContext(life, http.MethodPost, reqURL, pr)
	if err != nil {
		lifeCancel()
		pr.Close()
		pw.Close()
		return nil, nil, err
	}
	req.ContentLength = -1
	decorate(req, cfg, authCookie(msg1))

	type result struct {
		resp *http.Response
		err  error
	}
	ch := make(chan result, 1)
	var closeFn func()
	abort := func() {
		lifeCancel()
		if closeFn != nil {
			closeFn()
		} else {
			pw.Close()
			pr.Close()
		}
	}
	if h3 {
		tr, err := newH3(cfg, addr)
		if err != nil {
			abort()
			return nil, nil, err
		}
		closeFn = func() { tr.Close(); pw.Close() }
		go func() {
			resp, err := tr.RoundTrip(req)
			ch <- result{resp, err}
		}()
	} else {
		link, err := newH2(ctx, cfg, addr)
		if err != nil {
			abort()
			return nil, nil, err
		}
		closeFn = func() { link.Close(); pw.Close() }
		go func() {
			resp, err := link.tr.RoundTrip(req)
			ch <- result{resp, err}
		}()
	}
	var res result
	select {
	case res = <-ch:
	case <-ctx.Done():
		abort()
		return nil, nil, ctx.Err()
	case <-time.After(cfg.timeout()):
		abort()
		return nil, nil, errors.New("nox: таймаут рукопожатия")
	}
	if res.err != nil {
		abort()
		return nil, nil, res.err
	}
	resp := res.resp
	if resp.StatusCode != 200 || strings.Contains(resp.Header.Get("Content-Type"), "text/html") {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 64))
		resp.Body.Close()
		abort()
		if strings.Contains(http.DetectContentType(body), "text") || strings.Contains(resp.Header.Get("Content-Type"), "text/html") {
			return nil, nil, errors.New("nox: сервер ответил как обычный сайт (ключ не подошёл или канал закрыт)")
		}
		return nil, nil, errors.New("nox: неожиданный ответ " + resp.Status)
	}
	msg2, err := readMsg2(resp.Body)
	if err != nil {
		resp.Body.Close()
		abort()
		return nil, nil, err
	}
	send, recv, err := clientFinish(hs, msg2)
	if err != nil {
		resp.Body.Close()
		abort()
		return nil, nil, err
	}
	raw := rw{r: resp.Body, w: pw}
	fc := newFrameConn(raw, send, recv, cfg.Profile, cfg.jitter())
	return newSession(fc, false), func() {
		lifeCancel()
		resp.Body.Close()
		closeFn()
	}, nil
}

func readMsg2(r io.Reader) ([]byte, error) {
	var lb [2]byte
	if _, err := io.ReadFull(r, lb[:]); err != nil {
		return nil, err
	}
	n := binary.BigEndian.Uint16(lb[:])
	if n == 0 || n > 512 {
		return nil, errors.New("nox: сервер ответил не рукопожатием")
	}
	buf := make([]byte, n)
	if _, err := io.ReadFull(r, buf); err != nil {
		return nil, err
	}
	return buf, nil
}

func newH3(cfg Config, addr string) (*http3.Transport, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, err
	}
	tlsCfg := &tls.Config{
		ServerName:         cfg.SNI,
		InsecureSkipVerify: cfg.Insecure,
		NextProtos:         []string{http3.NextProtoH3},
		MinVersion:         tls.VersionTLS13,
	}
	tr := &http3.Transport{
		TLSClientConfig: tlsCfg,
		QUICConfig: &quic.Config{
			MaxIdleTimeout:                 90 * time.Second,
			HandshakeIdleTimeout:           cfg.timeout(),
			KeepAlivePeriod:                15 * time.Second,
			InitialStreamReceiveWindow:     6291456,
			InitialConnectionReceiveWindow: 15728640,
		},
		Dial: func(ctx context.Context, _ string, tc *tls.Config, qc *quic.Config) (*quic.Conn, error) {
			a := net.JoinHostPort(host, port)
			return quic.DialAddr(ctx, a, tc, qc)
		},
	}
	return tr, nil
}

func dialCDN(ctx context.Context, cfg Config) (*session, func(), error) {
	link, err := newH2(ctx, cfg, cfg.Addr)
	if err != nil {
		return nil, nil, err
	}
	id := Identity{Password: cfg.Password}
	msg1, hs, err := clientHello(id, cfg.Pub, time.Now())
	if err != nil {
		link.Close()
		return nil, nil, err
	}
	u := "https://" + cfg.authority() + cfg.path() + "?b=1"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, http.NoBody)
	if err != nil {
		link.Close()
		return nil, nil, err
	}
	decorate(req, cfg, authCookie(msg1))
	resp, err := link.tr.RoundTrip(req)
	if err != nil {
		link.Close()
		return nil, nil, err
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	resp.Body.Close()
	if err != nil {
		link.Close()
		return nil, nil, err
	}
	if resp.StatusCode != 200 || strings.Contains(resp.Header.Get("Content-Type"), "text/html") {
		link.Close()
		return nil, nil, errors.New("nox: CDN-канал отклонён")
	}
	if len(body) < 2 {
		link.Close()
		return nil, nil, errors.New("nox: пустой ответ CDN")
	}
	n := int(binary.BigEndian.Uint16(body[:2]))
	if 2+n > len(body) {
		link.Close()
		return nil, nil, errors.New("nox: битый ответ CDN")
	}
	send, recv, err := clientFinish(hs, body[2:2+n])
	if err != nil {
		link.Close()
		return nil, nil, err
	}
	nx := ""
	if c := nxCookie(resp); c != "" {
		nx = c
	}
	up, down := newBufPipe(256*1024), newBufPipe(256*1024)
	if rest := body[2+n:]; len(rest) > 0 {
		_, _ = down.Write(rest)
	}
	// Same as dialStream: later polls must not die when the dial context is cancelled.
	life, lifeCancel := context.WithCancel(context.Background())
	stop := make(chan struct{})
	go cdnPoll(life, cfg, link, nx, up, down, stop)
	fc := newFrameConn(rw{r: down, w: up}, send, recv, cfg.Profile, cfg.jitter())
	return newSession(fc, false), func() {
		lifeCancel()
		close(stop)
		up.Close()
		down.Close()
		link.Close()
	}, nil
}

func nxCookie(resp *http.Response) string {
	for _, c := range resp.Cookies() {
		if c.Name == "nx" {
			return c.Value
		}
	}
	return ""
}

func cdnPoll(ctx context.Context, cfg Config, link *h2link, nx string, up, down *bufPipe, stop <-chan struct{}) {
	u := "https://" + cfg.authority() + cfg.path() + "?b=1"
	for {
		select {
		case <-stop:
			return
		default:
		}
		chunk := up.take(32*1024, cfg.poll())
		var body io.Reader = http.NoBody
		if len(chunk) > 0 {
			body = bytes.NewReader(chunk)
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, body)
		if err != nil {
			return
		}
		decorate(req, cfg, "nx="+nx)
		if len(chunk) > 0 {
			req.ContentLength = int64(len(chunk))
		}
		resp, err := link.tr.RoundTrip(req)
		if err != nil {
			down.Close()
			return
		}
		b, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		resp.Body.Close()
		if err != nil || resp.StatusCode != 200 {
			down.Close()
			return
		}
		if len(b) > 0 {
			if _, err := down.Write(b); err != nil {
				return
			}
		}
	}
}
