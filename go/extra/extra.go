// Package extra runs protocols sing-box lacks (Snell, Mieru, TrustTunnel, ShadowQUIC via mihomo;
// Juicity via daeuniverse/outbound) in-process behind a loopback SOCKS5 port that sing-box dials.
package extra

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"sync"
	"time"
)

type rwc interface {
	io.ReadWriteCloser
}

type dialFn func(ctx context.Context, host string, port uint16) (rwc, error)

var kinds = map[string]func(cfg map[string]any) (dialFn, func(), error){}

// Local is one running loopback SOCKS5 server.
type Local struct {
	Port int
	ln   net.Listener
	stop func()
	once sync.Once
}

func (l *Local) Stop() {
	l.once.Do(func() {
		l.ln.Close()
		if l.stop != nil {
			l.stop()
		}
	})
}

// Start parses {"type":"_ext","kind":"mihomo|juicity","cfg":{...}} and serves it on 127.0.0.1:<random>.
func Start(raw []byte) (*Local, error) {
	var w struct {
		Kind string         `json:"kind"`
		Cfg  map[string]any `json:"cfg"`
	}
	if err := json.Unmarshal(raw, &w); err != nil {
		return nil, err
	}
	mk, ok := kinds[w.Kind]
	if !ok {
		return nil, fmt.Errorf("протокол %s не поддерживается этой сборкой", w.Kind)
	}
	dial, stop, err := mk(w.Cfg)
	if err != nil {
		return nil, err
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		if stop != nil {
			stop()
		}
		return nil, err
	}
	l := &Local{Port: ln.Addr().(*net.TCPAddr).Port, ln: ln, stop: stop}
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go serve(c, dial)
		}
	}()
	return l, nil
}

func serve(c net.Conn, dial dialFn) {
	defer c.Close()
	c.SetDeadline(time.Now().Add(15 * time.Second))
	b := make([]byte, 262)
	if _, err := io.ReadFull(c, b[:2]); err != nil || b[0] != 5 {
		return
	}
	if _, err := io.ReadFull(c, b[:b[1]]); err != nil {
		return
	}
	c.Write([]byte{5, 0})
	if _, err := io.ReadFull(c, b[:4]); err != nil || b[1] != 1 {
		c.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	var host string
	switch b[3] {
	case 1:
		io.ReadFull(c, b[:4])
		host = net.IP(b[:4]).String()
	case 4:
		io.ReadFull(c, b[:16])
		host = net.IP(b[:16]).String()
	case 3:
		io.ReadFull(c, b[:1])
		n := int(b[0])
		io.ReadFull(c, b[:n])
		host = string(b[:n])
	default:
		return
	}
	if _, err := io.ReadFull(c, b[:2]); err != nil {
		return
	}
	port := binary.BigEndian.Uint16(b[:2])
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	r, err := dial(ctx, host, port)
	cancel()
	if err != nil {
		c.Write([]byte{5, 5, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	defer r.Close()
	c.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0})
	c.SetDeadline(time.Time{})
	done := make(chan struct{}, 2)
	go func() { io.Copy(r, c); closeWrite(r); done <- struct{}{} }()
	go func() { io.Copy(c, r); closeWrite(c); done <- struct{}{} }()
	<-done
	<-done
}

func closeWrite(c io.Closer) {
	if cw, ok := c.(interface{ CloseWrite() error }); ok {
		cw.CloseWrite()
	} else {
		c.Close()
	}
}

var errNoHost = errors.New("пустой адрес")

func hostPort(h string, p uint16) string { return net.JoinHostPort(h, strconv.Itoa(int(p))) }
