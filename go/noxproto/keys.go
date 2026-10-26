// Package noxproto is the NOX cover transport (share-link scheme noxp://).
//
// Cryptography is the Noise framework (NKpsk0, X25519, ChaCha20-Poly1305,
// SHA-256) inside a real TLS 1.3 session. This package does not define a
// cipher; the novelty is the traffic shape and the way authentication is
// hidden from active probers.
package noxproto

import (
	"bufio"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/flynn/noise"
	"golang.org/x/crypto/hkdf"
)

// Identity is the server's long-term X25519 key and the subscription password.
// Clients authenticate with Noise_NKpsk0: they know Public, and both sides
// derive a 32-byte PSK from Password and Public.
type Identity struct {
	Private  []byte
	Public   []byte
	Password string
}

// NewIdentity generates a server key and a random password.
func NewIdentity() (Identity, error) {
	cs := noise.NewCipherSuite(noise.DH25519, noise.CipherChaChaPoly, noise.HashSHA256)
	kp, err := cs.GenerateKeypair(rand.Reader)
	if err != nil {
		return Identity{}, err
	}
	var pw [16]byte
	if _, err := rand.Read(pw[:]); err != nil {
		return Identity{}, err
	}
	return Identity{Private: kp.Private, Public: kp.Public, Password: hex.EncodeToString(pw[:])}, nil
}

// DerivePSK is the Noise preshared key. Empty passwords are allowed: the
// link itself is then the only secret, which is weaker if the public key leaks.
func DerivePSK(password string, serverPub []byte) []byte {
	r := hkdf.New(sha256.New, []byte(password), serverPub, []byte("noxp/psk-v1"))
	out := make([]byte, 32)
	if _, err := io.ReadFull(r, out); err != nil {
		panic("hkdf: " + err.Error())
	}
	return out
}

// ParsePub decodes a server public key from base64url, standard base64, or hex.
func ParsePub(s string) ([]byte, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, errors.New("nox: пустой ключ сервера")
	}
	for _, enc := range []*base64.Encoding{base64.RawURLEncoding, base64.URLEncoding, base64.RawStdEncoding, base64.StdEncoding} {
		if b, err := enc.DecodeString(s); err == nil && len(b) == 32 {
			return b, nil
		}
	}
	if b, err := hex.DecodeString(s); err == nil && len(b) == 32 {
		return b, nil
	}
	return nil, errors.New("nox: ключ сервера должен быть 32 байта (base64 или hex)")
}

// PubString is the form used in noxp:// links.
func PubString(pub []byte) string {
	return base64.RawURLEncoding.EncodeToString(pub)
}

// SaveIdentity writes a mode-0600 text file. The password is stored so the
// server and the subscription link stay in sync.
func SaveIdentity(path string, id Identity) error {
	if len(id.Private) != 32 || len(id.Public) != 32 {
		return errors.New("nox: неверный ключ")
	}
	if strings.ContainsAny(id.Password, "\r\n") {
		return errors.New("nox: пароль не должен содержать перевод строки")
	}
	body := fmt.Sprintf("nox-identity-v1\npriv %s\npub %s\npass %s\n",
		base64.RawURLEncoding.EncodeToString(id.Private),
		base64.RawURLEncoding.EncodeToString(id.Public),
		id.Password)
	return os.WriteFile(path, []byte(body), 0o600)
}

// LoadIdentity reads a file written by SaveIdentity.
func LoadIdentity(path string) (Identity, error) {
	f, err := os.Open(path)
	if err != nil {
		return Identity{}, err
	}
	defer f.Close()
	var id Identity
	sc := bufio.NewScanner(f)
	line := 0
	for sc.Scan() {
		line++
		t := strings.TrimSpace(sc.Text())
		if t == "" || strings.HasPrefix(t, "#") || t == "nox-identity-v1" {
			continue
		}
		k, v, ok := strings.Cut(t, " ")
		if !ok {
			return Identity{}, fmt.Errorf("nox: %s: строка %d", path, line)
		}
		switch k {
		case "priv":
			b, err := base64.RawURLEncoding.DecodeString(v)
			if err != nil || len(b) != 32 {
				return Identity{}, fmt.Errorf("nox: %s: закрытый ключ", path)
			}
			id.Private = b
		case "pub":
			b, err := base64.RawURLEncoding.DecodeString(v)
			if err != nil || len(b) != 32 {
				return Identity{}, fmt.Errorf("nox: %s: открытый ключ", path)
			}
			id.Public = b
		case "pass":
			id.Password = v
		default:
			return Identity{}, fmt.Errorf("nox: %s: неизвестное поле %q", path, k)
		}
	}
	if err := sc.Err(); err != nil {
		return Identity{}, err
	}
	if len(id.Private) != 32 || len(id.Public) != 32 {
		return Identity{}, fmt.Errorf("nox: %s: нет ключа", path)
	}
	return id, nil
}
