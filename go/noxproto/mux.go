package noxproto

import (
	"encoding/binary"
	"errors"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

// session multiplexes many streams over one Noise-protected carrier connection.
type session struct {
	fc   *frameConn
	done chan struct{}
	dead atomic.Bool

	mu      sync.Mutex
	streams map[uint32]*stream
	acks    map[uint32]chan error
	nextID  atomic.Uint32

	// onOpen is set on the server. It dials the target.
	onOpen func(f frame)
	once   sync.Once
}

func newSession(fc *frameConn, server bool) *session {
	s := &session{
		fc:      fc,
		done:    make(chan struct{}),
		streams: map[uint32]*stream{},
		acks:    map[uint32]chan error{},
	}
	if server {
		s.onOpen = s.dialOpen
	}
	go s.readLoop()
	go s.keepalive()
	return s
}

func (s *session) readLoop() {
	defer s.closeAll()
	for {
		f, err := s.fc.readFrame()
		if err != nil {
			return
		}
		switch f.typ {
		case frameOpen:
			if s.onOpen != nil {
				go s.onOpen(f)
			}
		case frameData, frameUDP:
			s.push(f)
		case frameClose:
			s.markClosed(f.id)
		case frameAck:
			s.deliverAck(f)
		case framePing:
		default:
		}
	}
}

func (s *session) keepalive() {
	t := time.NewTicker(20 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-s.done:
			return
		case <-t.C:
			if err := s.fc.writeFrame(frame{typ: framePing}); err != nil {
				s.closeAll()
				return
			}
		}
	}
}

func (s *session) closeAll() {
	s.once.Do(func() {
		s.dead.Store(true)
		close(s.done)
		s.mu.Lock()
		defer s.mu.Unlock()
		for id, st := range s.streams {
			st.remoteClose()
			delete(s.streams, id)
		}
		for id, ch := range s.acks {
			select {
			case ch <- errors.New("nox: соединение закрыто"):
			default:
			}
			delete(s.acks, id)
		}
	})
}

func (s *session) alive() bool { return s != nil && !s.dead.Load() }

func (s *session) push(f frame) {
	s.mu.Lock()
	st := s.streams[f.id]
	s.mu.Unlock()
	if st == nil {
		return
	}
	st.push(f.typ == frameUDP, f.data)
}

func (s *session) markClosed(id uint32) {
	s.mu.Lock()
	st := s.streams[id]
	delete(s.streams, id)
	s.mu.Unlock()
	if st != nil {
		st.remoteClose()
	}
}

func (s *session) deliverAck(f frame) {
	s.mu.Lock()
	ch := s.acks[f.id]
	delete(s.acks, f.id)
	s.mu.Unlock()
	if ch == nil {
		return
	}
	var err error
	if len(f.data) > 0 {
		err = errors.New(string(f.data))
	}
	ch <- err
}

func (s *session) allocID() uint32 {
	for {
		id := s.nextID.Add(1)
		if id != 0 {
			return id
		}
	}
}

// open starts a stream. network is "tcp" or "udp".
func (s *session) open(host string, port uint16, udp bool) (net.Conn, error) {
	if !s.alive() {
		return nil, errors.New("nox: соединение закрыто")
	}
	if len(host) == 0 || len(host) > 255 {
		return nil, errors.New("nox: неверный адрес")
	}
	id := s.allocID()
	st := newStream(s, id, udp)
	ack := make(chan error, 1)
	s.mu.Lock()
	s.streams[id] = st
	s.acks[id] = ack
	s.mu.Unlock()
	if err := s.fc.writeFrame(frame{typ: frameOpen, id: id, data: encodeOpen(host, port, udp)}); err != nil {
		s.drop(id)
		return nil, err
	}
	select {
	case err := <-ack:
		if err != nil {
			s.drop(id)
			return nil, err
		}
		return st, nil
	case <-s.done:
		return nil, errors.New("nox: соединение закрыто")
	case <-time.After(20 * time.Second):
		s.drop(id)
		return nil, errors.New("nox: нет ответа на открытие потока")
	}
}

func (s *session) drop(id uint32) {
	s.mu.Lock()
	delete(s.streams, id)
	delete(s.acks, id)
	s.mu.Unlock()
}

func encodeOpen(host string, port uint16, udp bool) []byte {
	b := make([]byte, 4+len(host))
	if udp {
		b[0] = 1
	}
	binary.BigEndian.PutUint16(b[1:3], port)
	b[3] = byte(len(host))
	copy(b[4:], host)
	return b
}

func decodeOpen(b []byte) (host string, port uint16, udp bool, err error) {
	if len(b) < 4 {
		return "", 0, false, errors.New("nox: короткое открытие")
	}
	udp = b[0] == 1
	port = binary.BigEndian.Uint16(b[1:3])
	n := int(b[3])
	if len(b) < 4+n || n == 0 {
		return "", 0, false, errors.New("nox: неверный адрес")
	}
	return string(b[4 : 4+n]), port, udp, nil
}

func (s *session) dialOpen(f frame) {
	host, port, udp, err := decodeOpen(f.data)
	if err != nil {
		_ = s.fc.writeFrame(frame{typ: frameAck, id: f.id, data: []byte(err.Error())})
		return
	}
	addr := net.JoinHostPort(host, itoa(port))
	var c net.Conn
	if udp {
		c, err = net.Dial("udp", addr)
	} else {
		c, err = net.DialTimeout("tcp", addr, 10*time.Second)
	}
	if err != nil {
		_ = s.fc.writeFrame(frame{typ: frameAck, id: f.id, data: []byte("dial: " + err.Error())})
		return
	}
	st := newStream(s, f.id, udp)
	s.mu.Lock()
	s.streams[f.id] = st
	s.mu.Unlock()
	if err := s.fc.writeFrame(frame{typ: frameAck, id: f.id}); err != nil {
		c.Close()
		s.markClosed(f.id)
		return
	}
	go s.pumpFrom(st, c)
	go s.pumpTo(st, c)
}

func (s *session) pumpFrom(st *stream, c net.Conn) {
	buf := make([]byte, 16*1024)
	for {
		n, err := c.Read(buf)
		if n > 0 {
			if werr := s.fc.writeData(st.id, buf[:n], st.udp); werr != nil {
				break
			}
		}
		if err != nil {
			break
		}
	}
	_ = s.fc.writeFrame(frame{typ: frameClose, id: st.id})
	c.Close()
	s.markClosed(st.id)
}

func (s *session) pumpTo(st *stream, c net.Conn) {
	defer c.Close()
	buf := make([]byte, 16*1024)
	for {
		n, err := st.Read(buf)
		if n > 0 {
			if _, werr := c.Write(buf[:n]); werr != nil {
				return
			}
		}
		if err != nil {
			return
		}
	}
}

func itoa(p uint16) string {
	if p == 0 {
		return "0"
	}
	var b [5]byte
	i := len(b)
	for p > 0 {
		i--
		b[i] = byte('0' + p%10)
		p /= 10
	}
	return string(b[i:])
}

type stream struct {
	s   *session
	id  uint32
	udp bool

	mu     sync.Mutex
	cond   *sync.Cond
	buf    []byte
	pkts   [][]byte
	remote bool
	local  bool
}

func newStream(s *session, id uint32, udp bool) *stream {
	st := &stream{s: s, id: id, udp: udp}
	st.cond = sync.NewCond(&st.mu)
	return st
}

func (st *stream) push(udp bool, p []byte) {
	st.mu.Lock()
	if udp {
		st.pkts = append(st.pkts, append([]byte(nil), p...))
	} else if len(p) > 0 {
		st.buf = append(st.buf, p...)
	}
	st.cond.Broadcast()
	st.mu.Unlock()
}

func (st *stream) remoteClose() {
	st.mu.Lock()
	st.remote = true
	st.cond.Broadcast()
	st.mu.Unlock()
}

func (st *stream) Read(p []byte) (int, error) {
	st.mu.Lock()
	defer st.mu.Unlock()
	for {
		if st.udp {
			if len(st.pkts) > 0 {
				pkt := st.pkts[0]
				st.pkts = st.pkts[1:]
				n := copy(p, pkt)
				if n < len(pkt) {
					// datagram larger than the buffer: drop the rest, like a UDP read
				}
				return n, nil
			}
		} else if len(st.buf) > 0 {
			n := copy(p, st.buf)
			st.buf = st.buf[n:]
			return n, nil
		}
		if st.remote || st.local {
			return 0, io.EOF
		}
		st.cond.Wait()
	}
}

func (st *stream) Write(p []byte) (int, error) {
	st.mu.Lock()
	closed := st.local || st.remote
	st.mu.Unlock()
	if closed {
		return 0, io.ErrClosedPipe
	}
	if err := st.s.fc.writeData(st.id, p, st.udp); err != nil {
		return 0, err
	}
	return len(p), nil
}

func (st *stream) Close() error {
	st.mu.Lock()
	if st.local {
		st.mu.Unlock()
		return nil
	}
	st.local = true
	st.cond.Broadcast()
	st.mu.Unlock()
	_ = st.s.fc.writeFrame(frame{typ: frameClose, id: st.id})
	st.s.mu.Lock()
	delete(st.s.streams, st.id)
	st.s.mu.Unlock()
	return nil
}

func (st *stream) LocalAddr() net.Addr  { return dummyAddr("nox") }
func (st *stream) RemoteAddr() net.Addr { return dummyAddr("nox") }

func (st *stream) SetDeadline(t time.Time) error {
	_ = st.SetReadDeadline(t)
	return nil
}
func (st *stream) SetReadDeadline(t time.Time) error {
	if t.IsZero() {
		return nil
	}
	d := time.Until(t)
	if d <= 0 {
		st.mu.Lock()
		st.remote = true
		st.cond.Broadcast()
		st.mu.Unlock()
		return nil
	}
	time.AfterFunc(d, func() {
		st.mu.Lock()
		st.remote = true
		st.cond.Broadcast()
		st.mu.Unlock()
	})
	return nil
}
func (st *stream) SetWriteDeadline(time.Time) error { return nil }

type dummyAddr string

func (d dummyAddr) Network() string { return string(d) }
func (d dummyAddr) String() string  { return string(d) }
