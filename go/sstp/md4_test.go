package sstp

import (
	"encoding/hex"
	"strings"
	"testing"
	"unicode/utf16"
)

// RFC 2759 §9.2
func TestMSCHAPv2RFC2759(t *testing.T) {
	u := utf16.Encode([]rune("clientPass"))
	b := make([]byte, 2*len(u))
	for i, r := range u {
		b[2*i], b[2*i+1] = byte(r), byte(r>>8)
	}
	ph := md4sum(b)
	wantPH, _ := hex.DecodeString("44EBBA8D5312B8D611474411F56989AE")
	if hex.EncodeToString(ph) != hex.EncodeToString(wantPH) {
		t.Fatalf("PasswordHash %X", ph)
	}
	authChal, _ := hex.DecodeString("5B5D7C7D7B3F2F3E3C2C602132262628")
	peerChal, _ := hex.DecodeString("21402324255E262A28295F2B3A337C7E")
	ch := challengeHash(peerChal, authChal, "User")
	wantCh, _ := hex.DecodeString("D02E4386BCE91226")
	if hex.EncodeToString(ch) != hex.EncodeToString(wantCh) {
		t.Fatalf("Challenge %X want %X", ch, wantCh)
	}
	wantNT, _ := hex.DecodeString("82309ECD8D708B5EA08FAA3981CD83544233114A3D85D6DF")
	got := ntResponse(authChal, peerChal, "User", "clientPass")
	if hex.EncodeToString(got) != hex.EncodeToString(wantNT) {
		t.Fatalf("NtResponse\n got %X\nwant %X", got, wantNT)
	}
	ar := authenticatorResponse("clientPass", got, peerChal, authChal, "User")
	if !strings.EqualFold(strings.TrimPrefix(ar, "S="), "407A5589115FD0D6209F510FE9C04566932CDA56") {
		t.Fatalf("AuthenticatorResponse %q", ar)
	}
}
