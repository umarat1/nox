package noxproto

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"time"

	"github.com/flynn/noise"
)

// Noise pattern NKpsk0 (Noise spec revision 34):
//
//	<- s
//	-> psk, e, es
//	<- e, ee
//
// The client knows the server static key. The PSK is mixed in before the
// first message, so a probe that does not have the password cannot produce
// a message the server will accept. Cipher suite: 25519 + ChaChaPoly + SHA256.
const (
	prologue       = "noxp/1"
	handshakeSkew  = 120 * time.Second
	payloadLen     = 24 // unix seconds (8) || random (16)
	replayRemember = 3 * time.Minute
)

func cipherSuite() noise.CipherSuite {
	return noise.NewCipherSuite(noise.DH25519, noise.CipherChaChaPoly, noise.HashSHA256)
}

func handshakeConfig(init bool, id Identity, peerPub []byte) noise.Config {
	cfg := noise.Config{
		CipherSuite:           cipherSuite(),
		Pattern:               noise.HandshakeNK,
		Initiator:             init,
		Prologue:              []byte(prologue),
		PresharedKey:          DerivePSK(id.Password, peerPub),
		PresharedKeyPlacement: 0, // psk0
	}
	if init {
		cfg.PeerStatic = peerPub
		cfg.PresharedKey = DerivePSK(id.Password, peerPub)
	} else {
		cfg.StaticKeypair = noise.DHKey{Private: id.Private, Public: id.Public}
		cfg.PresharedKey = DerivePSK(id.Password, id.Public)
	}
	return cfg
}

func clientPayload(now time.Time) ([]byte, error) {
	b := make([]byte, payloadLen)
	binary.BigEndian.PutUint64(b[:8], uint64(now.Unix()))
	if _, err := rand.Read(b[8:]); err != nil {
		return nil, err
	}
	return b, nil
}

func checkPayload(pt []byte, now time.Time) error {
	if len(pt) < 8 {
		return errors.New("nox: короткое приветствие")
	}
	ts := int64(binary.BigEndian.Uint64(pt[:8]))
	d := now.Unix() - ts
	if d < 0 {
		d = -d
	}
	if time.Duration(d)*time.Second > handshakeSkew {
		return errors.New("nox: часы клиента слишком расходятся с сервером")
	}
	return nil
}

// clientHello builds the first Noise message (cookie value, before base64).
func clientHello(id Identity, serverPub []byte, now time.Time) (msg []byte, hs *noise.HandshakeState, err error) {
	hs, err = noise.NewHandshakeState(handshakeConfig(true, Identity{Password: id.Password}, serverPub))
	if err != nil {
		return nil, nil, err
	}
	payload, err := clientPayload(now)
	if err != nil {
		return nil, nil, err
	}
	msg, _, _, err = hs.WriteMessage(nil, payload)
	if err != nil {
		return nil, nil, err
	}
	return msg, hs, nil
}

// clientFinish consumes the server's handshake message and returns
// (send, recv) cipher states.
func clientFinish(hs *noise.HandshakeState, msg2 []byte) (send, recv *noise.CipherState, err error) {
	_, cs1, cs2, err := hs.ReadMessage(nil, msg2)
	if err != nil {
		return nil, nil, err
	}
	if cs1 == nil || cs2 == nil {
		return nil, nil, errors.New("nox: рукопожатие не завершено")
	}
	// Split() yields (initiator->responder, responder->initiator).
	return cs1, cs2, nil
}

// serverAccept checks replay and timestamp, then builds the reply message
// and the server's (send, recv) cipher states.
func serverAccept(id Identity, msg1 []byte, now time.Time, replay *replayCache) (msg2 []byte, send, recv *noise.CipherState, err error) {
	if len(msg1) < 32 {
		return nil, nil, nil, errors.New("nox: короткое приветствие")
	}
	var eph [32]byte
	copy(eph[:], msg1[:32])
	if replay != nil && replay.seen(eph) {
		return nil, nil, nil, errors.New("nox: повтор рукопожатия")
	}
	hs, err := noise.NewHandshakeState(handshakeConfig(false, id, nil))
	if err != nil {
		return nil, nil, nil, err
	}
	pt, _, _, err := hs.ReadMessage(nil, msg1)
	if err != nil {
		return nil, nil, nil, err
	}
	if err := checkPayload(pt, now); err != nil {
		return nil, nil, nil, err
	}
	if replay != nil && !replay.add(eph, now) {
		return nil, nil, nil, errors.New("nox: повтор рукопожатия")
	}
	msg2, cs1, cs2, err := hs.WriteMessage(nil, nil)
	if err != nil {
		return nil, nil, nil, err
	}
	if cs1 == nil || cs2 == nil {
		return nil, nil, nil, errors.New("nox: рукопожатие не завершено")
	}
	// Responder sends with the second cipher, receives with the first.
	return msg2, cs2, cs1, nil
}
