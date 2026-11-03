package engine

import (
	"crypto/ed25519"
	"encoding/base64"
	"testing"
)

func TestVerifySig(t *testing.T) {
	pub, priv, _ := ed25519.GenerateKey(nil)
	old := UpdatePubKey
	defer func() { UpdatePubKey = old }()
	UpdatePubKey = base64.StdEncoding.EncodeToString(pub)
	sum := "ab12"
	sig := base64.StdEncoding.EncodeToString(ed25519.Sign(priv, []byte(sum)))
	if !verifySig("AB12", sig) || verifySig("ab13", sig) || verifySig(sum, "") {
		t.Fatal("verify")
	}
}
