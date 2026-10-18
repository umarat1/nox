package sstp

import (
	"encoding/binary"
	"fmt"
	"io"
)

// SSTP framing (MS-SSTP): every message starts with Version(1)=0x10, C(1 bit)|Reserved,
// LengthPacket(2). Control messages then have MessageType(2), NumAttributes(2) + attrs.
// Data messages carry a PPP frame (protocol + payload, no HDLC flags/FCS).

func (s *Session) writeControl(msg uint16, attrs ...[]byte) error {
	var body []byte
	for _, a := range attrs {
		body = append(body, a...)
	}
	h := make([]byte, 8+len(body))
	h[0] = sstpVersion
	h[1] = 0x01 // C bit (accel-ppp / Windows wire format: low bit)
	binary.BigEndian.PutUint16(h[2:], uint16(len(h)))
	binary.BigEndian.PutUint16(h[4:], msg)
	binary.BigEndian.PutUint16(h[6:], uint16(len(attrs)))
	copy(h[8:], body)
	s.wmu.Lock()
	defer s.wmu.Unlock()
	_, err := s.conn.Write(h)
	return err
}

func attr(id uint16, v []byte) []byte {
	a := make([]byte, 4+len(v))
	binary.BigEndian.PutUint16(a[0:], id)
	binary.BigEndian.PutUint16(a[2:], uint16(len(a)))
	copy(a[4:], v)
	return a
}

func (s *Session) writeData(ppp []byte) error {
	h := make([]byte, 4+len(ppp))
	h[0] = sstpVersion
	binary.BigEndian.PutUint16(h[2:], uint16(len(h)))
	copy(h[4:], ppp)
	s.wmu.Lock()
	defer s.wmu.Unlock()
	_, err := s.conn.Write(h)
	return err
}

func (s *Session) writePPP(proto uint16, p []byte) error {
	// accel-ppp (and Windows) speak PPP with HDLC Address/Control 0xff 0x03 over SSTP,
	// even though MS-SSTP says those bytes are omitted. We send them for interoperability.
	b := make([]byte, 4+len(p))
	b[0], b[1] = 0xff, 0x03
	binary.BigEndian.PutUint16(b[2:], proto)
	copy(b[4:], p)
	return s.writeData(b)
}

// stripAC removes an optional PPP Address/Control prefix (0xff 0x03).
func stripAC(ppp []byte) []byte {
	if len(ppp) >= 2 && ppp[0] == 0xff && ppp[1] == 0x03 {
		return ppp[2:]
	}
	return ppp
}

// readFrame returns (isControl, msgType, payload, attrs, error). For data, payload is the PPP
// frame; for control, payload is unused and attrs is the attribute list.
func (s *Session) readFrame() (ctrl bool, msg uint16, ppp []byte, attrs [][]byte, err error) {
	var h [4]byte
	if _, err = io.ReadFull(s.br, h[:]); err != nil {
		return
	}
	if h[0] != sstpVersion {
		err = fmt.Errorf("SSTP: неизвестная версия 0x%02x", h[0])
		return
	}
	ctrl = h[1]&0x01 != 0
	n := int(binary.BigEndian.Uint16(h[2:]))
	if n < 4 || n > 1<<16 {
		err = fmt.Errorf("SSTP: плохая длина %d", n)
		return
	}
	body := make([]byte, n-4)
	if _, err = io.ReadFull(s.br, body); err != nil {
		return
	}
	if !ctrl {
		ppp = body
		return
	}
	if len(body) < 4 {
		err = fmt.Errorf("SSTP: короткое управляющее сообщение")
		return
	}
	msg = binary.BigEndian.Uint16(body[0:])
	na := int(binary.BigEndian.Uint16(body[2:]))
	rest := body[4:]
	for i := 0; i < na; i++ {
		if len(rest) < 4 {
			err = fmt.Errorf("SSTP: обрезанный атрибут")
			return
		}
		al := int(binary.BigEndian.Uint16(rest[2:]))
		if al < 4 || al > len(rest) {
			err = fmt.Errorf("SSTP: плохая длина атрибута %d", al)
			return
		}
		attrs = append(attrs, rest[:al])
		rest = rest[al:]
	}
	return
}

func attrID(a []byte) uint16  { return binary.BigEndian.Uint16(a[0:]) }
func attrVal(a []byte) []byte { return a[4:] }
