package sstp

import (
	"crypto/hmac"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/x509"
	"encoding/binary"
)

func hmacSHA1(key, msg []byte) []byte {
	m := hmac.New(sha1.New, key)
	m.Write(msg)
	return m.Sum(nil)
}

func hmacSHA256(key, msg []byte) []byte {
	m := hmac.New(sha256.New, key)
	m.Write(msg)
	return m.Sum(nil)
}

func certHash(cert *x509.Certificate, proto byte) []byte {
	out := make([]byte, 32)
	if cert == nil {
		return out
	}
	if proto == hashSHA1 {
		s := sha1.Sum(cert.Raw)
		copy(out, s[:])
		return out
	}
	s := sha256.Sum256(cert.Raw)
	copy(out, s[:])
	return out
}

// compoundMAC returns the Crypto Binding attribute value (Reserved|HashProto|Nonce|CertHash|CMAC).
func compoundMAC(proto byte, nonce, certH, sendKey []byte) (attrVal []byte, _ []byte) {
	inner := []byte("SSTP inner method derived CMK")
	var cmk []byte
	if proto == hashSHA1 {
		cmk = hmacSHA1(sendKey, inner)
	} else {
		cmk = hmacSHA256(sendKey, inner)
	}
	val := make([]byte, 3+1+32+32+32)
	val[3] = proto
	copy(val[4:], nonce)
	copy(val[36:], certH)
	a := attr(attrCryptoBinding, val) // CMAC still zero
	msg := make([]byte, 8+len(a))
	msg[0] = sstpVersion
	msg[1] = 0x01
	binary.BigEndian.PutUint16(msg[2:], uint16(len(msg)))
	binary.BigEndian.PutUint16(msg[4:], msgConnected)
	binary.BigEndian.PutUint16(msg[6:], 1)
	copy(msg[8:], a)
	var cmac []byte
	if proto == hashSHA1 {
		cmac = make([]byte, 32)
		copy(cmac, hmacSHA1(cmk, msg))
	} else {
		cmac = hmacSHA256(cmk, msg)
	}
	copy(val[68:], cmac[:32])
	return val, nil
}
