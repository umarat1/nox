// Package sstp is a pure-Go SSTP client (MS-SSTP over TLS) with the PPP it carries: LCP,
// MS-CHAPv2 / CHAP-MD5 / PAP, IPCP (IPv4 + DNS) and SSTP crypto binding. It yields a raw IPv4
// packet link (ReadPacket / WritePacket) for Android's VpnService TUN.
package sstp

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type Config struct {
	Server   string // hostname (TLS SNI default, HTTP Host)
	Addr     string // optional pre-resolved IP to dial (default: Server)
	Port     int
	User     string
	Password string
	SNI      string
	Insecure bool
	// Dial for the TLS transport (nil: net.Dialer). On Android the app is outside its own VPN.
	Dial func(ctx context.Context, network, addr string) (net.Conn, error)
	Logf func(format string, a ...any)
}

type Session struct {
	LocalIP net.IP
	PeerIP  net.IP
	DNS     []net.IP
	MTU     int
	Auth    string

	cfg    Config
	conn   net.Conn
	br     *bufio.Reader
	wmu    sync.Mutex
	in     chan []byte
	done   chan struct{}
	once   sync.Once
	err    error
	magic  uint32
	lcpID  byte
	peer   *x509.Certificate
	Rx, Tx atomic.Uint64
}

const (
	sstpVersion = 0x10

	msgConnectRequest = 1
	msgConnectAck     = 2
	msgConnectNak     = 3
	msgConnected      = 4
	msgAbort          = 5
	msgDisconnect     = 6
	msgDisconnectAck  = 7
	msgEchoRequest    = 8
	msgEchoResponse   = 9

	attrEncapProto    = 1
	attrCryptoBinding = 3
	attrCryptoBindReq = 4
	hashSHA1          = 1
	hashSHA256        = 2

	protoLCP  = 0xc021
	protoPAP  = 0xc023
	protoCHAP = 0xc223
	protoIPCP = 0x8021
	protoIPv4 = 0x0021

	confReq, confAck   = 1, 2
	confNak, confRej   = 3, 4
	termReq, termAck   = 5, 6
	codeRej, protoRej  = 7, 8
	echoReq, echoReply = 9, 10
)

var ErrAuth = errors.New("SSTP: неверный логин или пароль")

func (s *Session) logf(f string, a ...any) {
	if s.cfg.Logf != nil {
		s.cfg.Logf(f, a...)
	}
}

// Dial connects and negotiates up to an open IPv4 link.
func Dial(ctx context.Context, cfg Config) (*Session, error) {
	if cfg.Port == 0 {
		cfg.Port = 443
	}
	s := &Session{cfg: cfg, in: make(chan []byte, 256), done: make(chan struct{}), MTU: 1400}
	var mb [4]byte
	if _, err := io.ReadFull(randReader{}, mb[:]); err != nil {
		return nil, err
	}
	s.magic = binary.BigEndian.Uint32(mb[:])
	addr := cfg.Addr
	if addr == "" {
		addr = cfg.Server
	}
	dial := cfg.Dial
	if dial == nil {
		dial = (&net.Dialer{Timeout: 15 * time.Second}).DialContext
	}
	raw, err := dial(ctx, "tcp", net.JoinHostPort(addr, strconv.Itoa(cfg.Port)))
	if err != nil {
		return nil, fmt.Errorf("SSTP: нет соединения с сервером: %w", err)
	}
	sni := cfg.SNI
	if sni == "" {
		sni = cfg.Server
	}
	tc := tls.Client(raw, &tls.Config{ServerName: sni, InsecureSkipVerify: cfg.Insecure, MinVersion: tls.VersionTLS12})
	dl, ok := ctx.Deadline()
	if !ok {
		dl = time.Now().Add(45 * time.Second)
	}
	tc.SetDeadline(dl)
	if err := tc.HandshakeContext(ctx); err != nil {
		raw.Close()
		return nil, fmt.Errorf("SSTP: TLS: %w", err)
	}
	if st := tc.ConnectionState(); len(st.PeerCertificates) > 0 {
		s.peer = st.PeerCertificates[0]
	}
	s.conn, s.br = tc, bufio.NewReaderSize(tc, 16<<10)
	stop := context.AfterFunc(ctx, func() { tc.SetDeadline(time.Unix(1, 0)) })
	err = s.handshake()
	stop()
	if err != nil {
		tc.Close()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, err
	}
	tc.SetDeadline(time.Time{})
	go s.readLoop()
	go s.keepalive()
	return s, nil
}

type randReader struct{}

func (randReader) Read(p []byte) (int, error) {
	return cryptoRandRead(p)
}

func (s *Session) handshake() error {
	host := s.cfg.Server
	if s.cfg.Port != 443 {
		host = net.JoinHostPort(host, strconv.Itoa(s.cfg.Port))
	}
	var g [16]byte
	cryptoRandRead(g[:])
	guid := fmt.Sprintf("{%X-%X-%X-%X-%X}", g[0:4], g[4:6], g[6:8], g[8:10], g[10:16])
	req := "SSTP_DUPLEX_POST /sra_{BA195980-CD49-458b-9E23-C84EE0ADCD75}/ HTTP/1.1\r\n" +
		"Host: " + host + "\r\nSSTPCORRELATIONID: " + guid + "\r\nContent-Length: 18446744073709551615\r\n\r\n"
	if _, err := io.WriteString(s.conn, req); err != nil {
		return err
	}
	line, err := s.br.ReadString('\n')
	if err != nil {
		return fmt.Errorf("SSTP: нет ответа HTTP: %w", err)
	}
	if f := strings.Fields(line); len(f) < 2 || f[1] != "200" {
		return fmt.Errorf("SSTP: сервер ответил %q", strings.TrimSpace(line))
	}
	for {
		l, err := s.br.ReadString('\n')
		if err != nil {
			return err
		}
		if strings.TrimSpace(l) == "" {
			break
		}
	}
	if err := s.writeControl(msgConnectRequest, attr(attrEncapProto, []byte{0, 1})); err != nil {
		return err
	}
	var nonce []byte
	var hashBits uint8
	for {
		ctrl, msg, ppp, attrs, err := s.readFrame()
		if err != nil {
			return fmt.Errorf("SSTP: Call Connect Ack: %w", err)
		}
		if !ctrl {
			s.logf("SSTP: unexpected data before Ack len=%d head=%x", len(ppp), ppp[:min(8, len(ppp))])
			continue
		}
		s.logf("SSTP: ctrl msg=%d attrs=%d", msg, len(attrs))
		if msg == msgConnectNak || msg == msgAbort {
			return fmt.Errorf("SSTP: сервер отклонил соединение")
		}
		if msg != msgConnectAck {
			continue
		}
		for _, a := range attrs {
			if attrID(a) == attrCryptoBindReq {
				v := attrVal(a)
				if len(v) >= 36 {
					hashBits = v[3]
					nonce = append([]byte{}, v[4:36]...)
				}
			}
		}
		break
	}
	s.logf("SSTP: Call Connect Ack (hashBits=%d)", hashBits)
	if err := s.negotiatePPP(hashBits, nonce); err != nil {
		return err
	}
	s.logf("SSTP: IP %s → %s DNS %v auth %s", s.LocalIP, s.PeerIP, s.DNS, s.Auth)
	return nil
}

// ReadPacket returns the next IPv4 packet from the server. Blocks until one arrives or the
// session is closed.
func (s *Session) ReadPacket() ([]byte, error) {
	select {
	case <-s.done:
		if s.err != nil {
			return nil, s.err
		}
		return nil, io.EOF
	case p, ok := <-s.in:
		if !ok {
			return nil, io.EOF
		}
		s.Rx.Add(uint64(len(p)))
		return p, nil
	}
}

// WritePacket sends one IPv4 packet to the server.
func (s *Session) WritePacket(p []byte) error {
	select {
	case <-s.done:
		if s.err != nil {
			return s.err
		}
		return io.EOF
	default:
	}
	if err := s.writePPP(protoIPv4, p); err != nil {
		return err
	}
	s.Tx.Add(uint64(len(p)))
	return nil
}

func (s *Session) Close() error {
	s.once.Do(func() {
		_ = s.writeControl(msgDisconnect)
		s.conn.Close()
		close(s.done)
	})
	return s.err
}

func (s *Session) readLoop() {
	for {
		ctrl, msg, ppp, _, err := s.readFrame()
		if err != nil {
			s.once.Do(func() {
				s.err = err
				close(s.done)
			})
			return
		}
		if ctrl {
			switch msg {
			case msgEchoRequest:
				_ = s.writeControl(msgEchoResponse)
			case msgAbort, msgDisconnect:
				_ = s.writeControl(msgDisconnectAck)
				s.once.Do(func() {
					s.err = fmt.Errorf("SSTP: сервер разорвал соединение")
					close(s.done)
				})
				return
			}
			continue
		}
		ppp = stripAC(ppp)
		if len(ppp) < 2 {
			continue
		}
		proto := binary.BigEndian.Uint16(ppp[0:])
		body := ppp[2:]
		switch proto {
		case protoIPv4:
			pkt := append([]byte{}, body...)
			select {
			case s.in <- pkt:
			case <-s.done:
				return
			}
		case protoLCP:
			if len(body) >= 4 && body[0] == echoReq {
				mb := make([]byte, 4)
				binary.BigEndian.PutUint32(mb, s.magic)
				_ = s.writePPP(protoLCP, pppCtl(echoReply, body[1], append(mb, body[4:]...)))
			}
		}
	}
}

func (s *Session) keepalive() {
	t := time.NewTicker(20 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-s.done:
			return
		case <-t.C:
			_ = s.writeControl(msgEchoRequest)
		}
	}
}
