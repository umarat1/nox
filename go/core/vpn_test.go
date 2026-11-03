package core

import "testing"

func TestSstpNoOvpn(t *testing.T) {
	// Nox 1.0: .ovpn content is not a server
	ov := "client\ndev tun\nproto udp\nremote 1.2.3.4 21194\n<ca>\nX\n</ca>\n"
	if r := ParseContent(ov); len(r.Servers) != 0 {
		t.Fatal("ovpn parsed", r)
	}
	s, err := ParseLink("sstp://u%40x:p%3Aw@vpn.example.com:8443?sni=cdn.example.com&dns=1.1.1.1#%F0%9F%87%AC%F0%9F%87%A7%20London")
	if err != nil || s.Type != "SSTP" || s.Port != 8443 {
		t.Fatal(s, err)
	}
	q, _ := SSTPFrom(s.Outbound)
	if q.User != "u@x" || q.Password != "p:w" || q.SNI != "cdn.example.com" || s.Name != "🇬🇧 London" {
		t.Fatal(q, s.Name)
	}
	if !IsLegacyOpenVPN([]byte(`{"type":"_openvpn"}`)) || IsFullTunnel([]byte(`{"type":"_openvpn"}`)) {
		t.Fatal("legacy")
	}
}
