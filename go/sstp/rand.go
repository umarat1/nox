package sstp

import "crypto/rand"

func cryptoRandRead(p []byte) (int, error) { return rand.Read(p) }
