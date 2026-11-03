package extra

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"time"
)

// ViaKey in an _ext cfg routes the protocol's own dials through an HTTP CONNECT proxy
// (2.3.3 «МТС прокси»: mieru → 192.168.192.192:80 → server). TCP only.
const ViaKey = "_nox_via"

// connectDialer is a mihomo C.Dialer that tunnels every TCP dial through an HTTP proxy.
type connectDialer struct{ proxy string }

func (d connectDialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
	if !strings.HasPrefix(network, "tcp") {
		return nil, fmt.Errorf("МТС прокси: %s не идёт через HTTP-прокси", network)
	}
	return httpConnect(ctx, d.proxy, address)
}

func (d connectDialer) ListenPacket(context.Context, string, string, netip.AddrPort) (net.PacketConn, error) {
	return nil, errors.New("МТС прокси: UDP не идёт через HTTP-прокси")
}

type bufConn struct {
	net.Conn
	r *bufio.Reader
}

func (c *bufConn) Read(b []byte) (int, error) { return c.r.Read(b) }

// httpConnect opens a CONNECT tunnel to address via the HTTP proxy at proxy (host:port).
func httpConnect(ctx context.Context, proxy, address string) (net.Conn, error) {
	var nd net.Dialer
	nd.Timeout = 15 * time.Second
	c, err := nd.DialContext(ctx, "tcp", proxy)
	if err != nil {
		return nil, err
	}
	if dl, ok := ctx.Deadline(); ok {
		c.SetDeadline(dl)
	} else {
		c.SetDeadline(time.Now().Add(15 * time.Second))
	}
	if _, err := fmt.Fprintf(c, "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", address, address); err != nil {
		c.Close()
		return nil, err
	}
	br := bufio.NewReader(c)
	resp, err := http.ReadResponse(br, &http.Request{Method: "CONNECT"})
	if err != nil {
		c.Close()
		return nil, fmt.Errorf("HTTP-прокси %s: %w", proxy, err)
	}
	if resp.StatusCode != 200 {
		c.Close()
		return nil, fmt.Errorf("HTTP-прокси %s: CONNECT %s → %s", proxy, address, resp.Status)
	}
	c.SetDeadline(time.Time{})
	if br.Buffered() > 0 {
		return &bufConn{Conn: c, r: br}, nil
	}
	return c, nil
}
