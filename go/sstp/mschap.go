package sstp

import (
	"crypto/des"
	"crypto/sha1"
	"encoding/hex"
	"strings"
	"unicode/utf16"
)

// MS-CHAPv2 (RFC 2759) and the MPPE master keys (RFC 3079) that SSTP's crypto binding uses.

func ntPasswordHash(pw string) []byte {
	u := utf16.Encode([]rune(pw))
	b := make([]byte, 2*len(u))
	for i, r := range u {
		b[2*i], b[2*i+1] = byte(r), byte(r>>8)
	}
	return md4sum(b)
}

func challengeHash(peerChal, authChal []byte, user string) []byte {
	h := sha1.New()
	h.Write(peerChal)
	h.Write(authChal)
	h.Write([]byte(user))
	return h.Sum(nil)[:8]
}

// desKey expands 7 key bytes to an 8-byte DES key (parity bits are ignored by crypto/des).
func desKey(k []byte) []byte {
	o := make([]byte, 8)
	o[0] = k[0]
	o[1] = k[0]<<7 | k[1]>>1
	o[2] = k[1]<<6 | k[2]>>2
	o[3] = k[2]<<5 | k[3]>>3
	o[4] = k[3]<<4 | k[4]>>4
	o[5] = k[4]<<3 | k[5]>>5
	o[6] = k[5]<<2 | k[6]>>6
	o[7] = k[6] << 1
	return o
}

func challengeResponse(chal, pwHash []byte) []byte {
	z := make([]byte, 21)
	copy(z, pwHash)
	out := make([]byte, 24)
	for i := 0; i < 3; i++ {
		c, _ := des.NewCipher(desKey(z[7*i : 7*i+7]))
		c.Encrypt(out[8*i:], chal)
	}
	return out
}

func ntResponse(authChal, peerChal []byte, user, pw string) []byte {
	return challengeResponse(challengeHash(peerChal, authChal, user), ntPasswordHash(pw))
}

var (
	authMagic1 = []byte("Magic server to client signing constant")
	authMagic2 = []byte("Pad to make it do more than one iteration")
)

// authenticatorResponse: the "S=…" string a genuine server returns in CHAP Success.
func authenticatorResponse(pw string, ntResp, peerChal, authChal []byte, user string) string {
	hh := md4sum(ntPasswordHash(pw))
	h := sha1.New()
	h.Write(hh)
	h.Write(ntResp)
	h.Write(authMagic1)
	d := h.Sum(nil)
	h = sha1.New()
	h.Write(d)
	h.Write(challengeHash(peerChal, authChal, user))
	h.Write(authMagic2)
	return "S=" + strings.ToUpper(hex.EncodeToString(h.Sum(nil)))
}

var (
	mppeMagic1 = []byte("This is the MPPE Master Key")
	mppeMagic2 = []byte("On the client side, this is the send key; on the server side, it is the receive key.")
	mppeMagic3 = []byte("On the client side, this is the receive key; on the server side, it is the send key.")
)

// mppeKeys returns the client's 16-byte MasterSendKey and MasterReceiveKey.
func mppeKeys(pw string, ntResp []byte) (send, recv []byte) {
	h := sha1.New()
	h.Write(md4sum(ntPasswordHash(pw)))
	h.Write(ntResp)
	h.Write(mppeMagic1)
	master := h.Sum(nil)[:16]
	start := func(magic []byte) []byte {
		h := sha1.New()
		h.Write(master)
		h.Write(make([]byte, 40))
		h.Write(magic)
		pad := make([]byte, 40)
		for i := range pad {
			pad[i] = 0xf2
		}
		h.Write(pad)
		return h.Sum(nil)[:16]
	}
	return start(mppeMagic2), start(mppeMagic3)
}
