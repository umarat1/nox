// signupdate: sign an installer for Nox auto-update.
//
//	signupdate -key <ed25519 private key file (64-byte seed+pub, base64)> <file>
//	signupdate -key-env NOX_UPDATE_KEY <file>
//
// prints {"sha256": "...", "sig": "..."} for version.json ("nox2-windows" entry).
// keygen: signupdate -gen <keyfile>  (writes private key 0600, prints the public key only)
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

func main() {
	key := flag.String("key", "", "private key file")
	keyEnv := flag.String("key-env", "", "read the private key from this environment variable instead (CI secrets)")
	gen := flag.String("gen", "", "generate a new key into this file")
	flag.Parse()
	if *gen != "" {
		if _, err := os.Stat(*gen); err == nil {
			fmt.Fprintln(os.Stderr, "exists:", *gen)
			os.Exit(1)
		}
		pub, priv, _ := ed25519.GenerateKey(rand.Reader)
		if err := os.WriteFile(*gen, []byte(base64.StdEncoding.EncodeToString(priv)+"\n"), 0o600); err != nil {
			panic(err)
		}
		fmt.Println(base64.StdEncoding.EncodeToString(pub))
		return
	}
	var b []byte
	var err error
	if *keyEnv != "" {
		b = []byte(os.Getenv(*keyEnv))
	} else if b, err = os.ReadFile(*key); err != nil {
		panic(err)
	}
	priv, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(b)))
	if err != nil || len(priv) != ed25519.PrivateKeySize {
		panic("bad key")
	}
	f, err := os.Open(flag.Arg(0))
	if err != nil {
		panic(err)
	}
	h := sha256.New()
	io.Copy(h, f)
	sum := hex.EncodeToString(h.Sum(nil))
	sig := ed25519.Sign(ed25519.PrivateKey(priv), []byte(sum))
	json.NewEncoder(os.Stdout).Encode(map[string]string{"sha256": sum, "sig": base64.StdEncoding.EncodeToString(sig)})
}
