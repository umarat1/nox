package sstp

import "golang.org/x/crypto/md4"

func md4sum(msg []byte) []byte {
	h := md4.New()
	h.Write(msg)
	return h.Sum(nil)
}
