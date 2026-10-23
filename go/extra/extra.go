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

type proto struct {
	dialTCP dialFn
	dialUDP dialFn
	stop    func()
}

var kinds = map[string]func(cfg map[string]any) (proto, error){}

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
	pr, err := mk(w.Cfg)
	if err != nil {
		return nil, err
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		if pr.stop != nil {
			pr.stop()
		}
		return nil, err
	}
	l := &Local{Port: ln.Addr().(*net.TCPAddr).Port, ln: ln, stop: pr.stop}
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go serve(c, pr)
		}
	}()
	return l, nil
}

func serve(c net.Conn, pr proto) {
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
	if _, err := io.ReadFull(c, b[:4]); err != nil || b[0] != 5 {
		return
	}
	cmd := b[1]
	if cmd != 1 && cmd != 3 {
		c.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	var host string
	switch b[3] {
	case 1:
		if _, err := io.ReadFull(c, b[:4]); err != nil {
			return
		}
		host = net.IP(b[:4]).String()
	case 4:
		if _, err := io.ReadFull(c, b[:16]); err != nil {
			return
		}
		host = net.IP(b[:16]).String()
	case 3:
		if _, err := io.ReadFull(c, b[:1]); err != nil {
			return
		}
		n := int(b[0])
		if _, err := io.ReadFull(c, b[:n]); err != nil {
			return
		}
		host = string(b[:n])
	default:
		return
	}
	if _, err := io.ReadFull(c, b[:2]); err != nil {
		return
	}
	port := binary.BigEndian.Uint16(b[:2])

	if cmd == 3 {
		serveUDPAssociate(c, pr.dialUDP)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	r, err := pr.dialTCP(ctx, host, port)
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

type udpSess struct {
	mu  sync.Mutex
	r   rwc
	hdr []byte
}

func serveUDPAssociate(c net.Conn, dialUDP dialFn) {
	if dialUDP == nil {
		c.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	uConn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 0})
	if err != nil {
		c.Write([]byte{5, 1, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	defer uConn.Close()
	uPort := uint16(uConn.LocalAddr().(*net.UDPAddr).Port)
	rep := []byte{5, 0, 0, 1, 127, 0, 0, 1, byte(uPort >> 8), byte(uPort)}
	if _, err := c.Write(rep); err != nil {
		return
	}
	c.SetDeadline(time.Time{})

	var (
		mu         sync.Mutex
		sessions   = map[string]*udpSess{}
		clientAddr *net.UDPAddr
		closed     bool
	)
	defer func() {
		mu.Lock()
		closed = true
		for k, s := range sessions {
			if s.r != nil {
				s.r.Close()
			}
			delete(sessions, k)
		}
		mu.Unlock()
	}()

	go func() {
		buf := make([]byte, 65535)
		for {
			n, src, err := uConn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			dstHost, dstPort, hdr, payload, ok := parseSocks5UDP(buf[:n])
			if !ok {
				continue
			}
			mu.Lock()
			clientAddr = src
			key := hostPort(dstHost, dstPort)
			sess := sessions[key]
			if sess == nil && !closed {
				sess = &udpSess{hdr: hdr}
				sessions[key] = sess
			}
			mu.Unlock()
			if sess == nil {
				continue
			}
			go func(s *udpSess, host string, port uint16, key string, data []byte) {
				s.mu.Lock()
				if s.r == nil {
					ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
					r, err := dialUDP(ctx, host, port)
					cancel()
					if err != nil {
						s.mu.Unlock()
						mu.Lock()
						if sessions[key] == s {
							delete(sessions, key)
						}
						mu.Unlock()
						return
					}
					s.r = r
					go func() {
						rbuf := make([]byte, 65535)
						for {
							rn, err := r.Read(rbuf)
							if err != nil {
								r.Close()
								mu.Lock()
								if sessions[key] == s {
									delete(sessions, key)
								}
								mu.Unlock()
								return
							}
							out := make([]byte, len(s.hdr)+rn)
							copy(out, s.hdr)
							copy(out[len(s.hdr):], rbuf[:rn])
							mu.Lock()
							ca := clientAddr
							mu.Unlock()
							if ca != nil {
								uConn.WriteToUDP(out, ca)
							}
						}
					}()
				}
				r := s.r
				s.mu.Unlock()
				if r != nil {
					r.Write(data)
				}
			}(sess, dstHost, dstPort, key, append([]byte(nil), payload...))
		}
	}()

	io.Copy(io.Discard, c)
}

func parseSocks5UDP(pkt []byte) (host string, port uint16, hdr []byte, payload []byte, ok bool) {
	if len(pkt) < 10 || pkt[0] != 0 || pkt[1] != 0 || pkt[2] != 0 {
		return "", 0, nil, nil, false
	}
	var hdrLen int
	switch pkt[3] {
	case 1:
		if len(pkt) < 10 {
			return "", 0, nil, nil, false
		}
		host = net.IP(pkt[4:8]).String()
		port = binary.BigEndian.Uint16(pkt[8:10])
		hdrLen = 10
	case 3:
		dlen := int(pkt[4])
		if len(pkt) < 7+dlen {
			return "", 0, nil, nil, false
		}
		host = string(pkt[5 : 5+dlen])
		port = binary.BigEndian.Uint16(pkt[5+dlen : 7+dlen])
		hdrLen = 7 + dlen
	case 4:
		if len(pkt) < 22 {
			return "", 0, nil, nil, false
		}
		host = net.IP(pkt[4:20]).String()
		port = binary.BigEndian.Uint16(pkt[20:22])
		hdrLen = 22
	default:
		return "", 0, nil, nil, false
	}
	return host, port, append([]byte(nil), pkt[:hdrLen]...), pkt[hdrLen:], true
}

var errNoHost = errors.New("пустой адрес")

func hostPort(h string, p uint16) string { return net.JoinHostPort(h, strconv.Itoa(int(p))) }
