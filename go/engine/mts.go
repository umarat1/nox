package engine

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"runtime"
	"time"

	"nox/core"
)

func (a *App) mtsOn() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.p.Settings.MtsProxy
}

// mtsTransport routes an HTTP client through the MTS operator proxy when the toggle is on.
func (a *App) mtsTransport(tr *http.Transport) {
	if a.mtsOn() {
		pu, _ := url.Parse(core.MtsProxyURL())
		tr.Proxy = http.ProxyURL(pu)
	}
}

// mtsDial opens a TCP connection to addr through the MTS HTTP proxy (CONNECT).
func mtsDial(ctx context.Context, network, addr string) (net.Conn, error) {
	if network != "tcp" && network != "tcp4" && network != "tcp6" {
		return nil, errors.New("МТС прокси: только TCP")
	}
	d := &net.Dialer{Timeout: 10 * time.Second}
	c, err := d.DialContext(ctx, "tcp", net.JoinHostPort(core.MtsProxyHost, fmt.Sprint(core.MtsProxyPort)))
	if err != nil {
		return nil, fmt.Errorf("МТС прокси недоступен: %w", err)
	}
	if dl, ok := ctx.Deadline(); ok {
		c.SetDeadline(dl)
	} else {
		c.SetDeadline(time.Now().Add(15 * time.Second))
	}
	fmt.Fprintf(c, "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", addr, addr)
	br := bufio.NewReader(c)
	resp, err := http.ReadResponse(br, &http.Request{Method: "CONNECT"})
	if err != nil {
		c.Close()
		return nil, fmt.Errorf("МТС прокси: %w", err)
	}
	if resp.StatusCode != 200 {
		c.Close()
		return nil, fmt.Errorf("МТС прокси: CONNECT %s — HTTP %d", addr, resp.StatusCode)
	}
	c.SetDeadline(time.Time{})
	if br.Buffered() > 0 {
		return &bufConn{Conn: c, r: br}, nil
	}
	return c, nil
}

type bufConn struct {
	net.Conn
	r *bufio.Reader
}

func (b *bufConn) Read(p []byte) (int, error) { return b.r.Read(p) }

// mtsUnsupported: "" when the server can be chained through the MTS HTTP proxy.
func mtsUnsupported(srv core.Server) string {
	switch {
	case srv.Type == "qWDTT":
		return "qWDTT (звонки VK, UDP/TURN) не работает через HTTP-прокси"
	case core.IsFullTunnel(srv.Outbound):
		if runtime.GOOS != "android" {
			return "SSTP через МТС прокси поддерживается только на Android"
		}
		return ""
	case core.IsXray(srv.Outbound):
		return ""
	case core.IsExt(srv.Outbound):
		var w struct{ Kind string }
		json.Unmarshal(srv.Outbound, &w)
		if w.Kind == "naive" {
			return "NaiveProxy (отдельное ядро) не умеет цепочку через HTTP-прокси МТС"
		}
		return srv.Type + " (внешнее ядро) не умеет цепочку через HTTP-прокси МТС"
	}
	var ob map[string]any
	if json.Unmarshal(srv.Outbound, &ob) == nil {
		return core.MtsBlocked(ob)
	}
	return ""
}

// MtsSupported is for the UI: false for servers that cannot go through the MTS proxy.
func MtsSupported(srv core.Server) bool { return mtsUnsupported(srv) == "" }

// mtsTCPPing: time to open a CONNECT tunnel to host:port through the MTS proxy (ms, -1 on failure).
func mtsTCPPing(host string, port int) int {
	if port == 0 {
		port = 443
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	t := time.Now()
	c, err := mtsDial(ctx, "tcp", net.JoinHostPort(host, fmt.Sprint(port)))
	if err != nil {
		return -1
	}
	c.Close()
	return int(time.Since(t).Milliseconds())
}
