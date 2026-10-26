package noxproto

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"io"
	"sync"
	"time"

	"github.com/flynn/noise"
)

const (
	frameOpen  = 1
	frameData  = 2
	frameClose = 3
	framePing  = 4
	frameUDP   = 5
	frameAck   = 6

	frameHeader = 7 // type + stream id + payload length
	maxPayload  = 32 * 1024
	maxCipher   = 40 * 1024
)

type frame struct {
	typ  byte
	id   uint32
	data []byte
}

func encodeFrame(f frame, target int) []byte {
	need := frameHeader + len(f.data)
	if target < need {
		target = need
	}
	buf := make([]byte, target)
	buf[0] = f.typ
	binary.BigEndian.PutUint32(buf[1:5], f.id)
	binary.BigEndian.PutUint16(buf[5:7], uint16(len(f.data)))
	copy(buf[7:], f.data)
	if target > need {
		_, _ = rand.Read(buf[need:])
	}
	return buf
}

func decodeFrame(pt []byte) (frame, error) {
	if len(pt) < frameHeader {
		return frame{}, errors.New("nox: короткий кадр")
	}
	n := int(binary.BigEndian.Uint16(pt[5:7]))
	if frameHeader+n > len(pt) || n > maxPayload {
		return frame{}, errors.New("nox: битый кадр")
	}
	f := frame{typ: pt[0], id: binary.BigEndian.Uint32(pt[1:5])}
	if n > 0 {
		f.data = append([]byte(nil), pt[7:7+n]...)
	}
	return f, nil
}

// frameConn carries padded Noise transport messages over a reliable stream.
type frameConn struct {
	r      io.Reader
	w      io.Writer
	send   *noise.CipherState
	recv   *noise.CipherState
	wmu    sync.Mutex
	prof   string
	jitter time.Duration
}

func newFrameConn(rw io.ReadWriter, send, recv *noise.CipherState, profile string, maxJitter time.Duration) *frameConn {
	return &frameConn{r: rw, w: rw, send: send, recv: recv, prof: normalizeProfile(profile), jitter: maxJitter}
}

func (c *frameConn) writeFrame(f frame) error {
	if len(f.data) > maxPayload {
		return errors.New("nox: слишком большой кадр")
	}
	pt := encodeFrame(f, sampleLen(c.prof))
	ct, err := c.send.Encrypt(nil, nil, pt)
	if err != nil {
		return err
	}
	if len(ct) > maxCipher {
		return errors.New("nox: кадр не влезает")
	}
	buf := make([]byte, 2+len(ct))
	binary.BigEndian.PutUint16(buf[:2], uint16(len(ct)))
	copy(buf[2:], ct)
	jitter(c.jitter)
	c.wmu.Lock()
	defer c.wmu.Unlock()
	_, err = c.w.Write(buf)
	return err
}

func (c *frameConn) readFrame() (frame, error) {
	var lb [2]byte
	if _, err := io.ReadFull(c.r, lb[:]); err != nil {
		return frame{}, err
	}
	n := int(binary.BigEndian.Uint16(lb[:]))
	if n < 16+frameHeader || n > maxCipher {
		return frame{}, errors.New("nox: неверная длина кадра")
	}
	ct := make([]byte, n)
	if _, err := io.ReadFull(c.r, ct); err != nil {
		return frame{}, err
	}
	pt, err := c.recv.Decrypt(nil, nil, ct)
	if err != nil {
		return frame{}, err
	}
	return decodeFrame(pt)
}

// writeData splits p into DATA or UDP frames.
func (c *frameConn) writeData(id uint32, p []byte, udp bool) error {
	typ := byte(frameData)
	if udp {
		typ = frameUDP
		if len(p) > maxPayload {
			return errors.New("nox: UDP-датаграмма больше 32 КБ")
		}
		return c.writeFrame(frame{typ: typ, id: id, data: p})
	}
	if len(p) == 0 {
		return c.writeFrame(frame{typ: typ, id: id})
	}
	for len(p) > 0 {
		n := len(p)
		if n > 12*1024 {
			n = 12 * 1024
		}
		if err := c.writeFrame(frame{typ: typ, id: id, data: p[:n]}); err != nil {
			return err
		}
		p = p[n:]
	}
	return nil
}
