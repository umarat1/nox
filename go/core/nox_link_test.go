package core

import "testing"

func TestNoxpLink(t *testing.T) {
	pub := "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	line := "noxp://" + pub + ":s3cret@vpn.example.com:443?carrier=h2,h3,cdn&sni=www.example.com&host=origin.example&path=/api/v1/events&profile=video&fp=firefox&front=cdn.example.com#NOX"
	if !IsShareLink(line) {
		t.Fatal("not a share link")
	}
	s, err := ParseLink(line)
	if err != nil {
		t.Fatal(err)
	}
	if s.Type != "NOX" || s.Host != "vpn.example.com" || s.Port != 443 || s.Name != "NOX" {
		t.Fatalf("%+v", s)
	}
	if !IsExt(s.Outbound) {
		t.Fatalf("outbound %s", s.Outbound)
	}
}
