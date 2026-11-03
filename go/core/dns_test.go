package core

import "testing"

func TestDNSServerChoice(t *testing.T) {
	cases := []struct{ dns, custom, typ, server string }{
		{"auto", "", "https", "1.1.1.1"},
		{"", "", "https", "1.1.1.1"},
		{"cloudflare", "", "https", "1.1.1.1"},
		{"google", "", "https", "8.8.8.8"},
		{"quad9", "", "https", "9.9.9.9"},
		{"adguard", "", "https", "94.140.14.14"},
		{"yandex", "", "udp", "77.88.8.8"},
		{"dnsai", "", "https", "dns.dns-ai.ru"},
		{"comss", "", "https", "dns.comss.one"},
		{"xbox", "", "https", "xbox-dns.ru"},
		{"controld", "", "https", "freedns.controld.com"},
		{"mullvad", "", "https", "dns.mullvad.net"},
		{"nextdns", "", "https", "dns.nextdns.io"},
		{"custom", "10.0.0.53", "udp", "10.0.0.53"},
		{"custom", "udp://2606:4700::1111", "udp", "2606:4700::1111"},
		{"custom", "https://dns.example/q", "https", "dns.example"},
		{"custom", "tls://dns.quad9.net", "tls", "dns.quad9.net"},
		{"custom", "not an ip", "https", "1.1.1.1"}, // invalid → safe default
	}
	for _, c := range cases {
		d := dnsServer(Settings{DNS: c.dns, CustomDNS: c.custom})
		if d["type"] != c.typ || d["server"] != c.server {
			t.Errorf("%s/%q: got %v", c.dns, c.custom, d)
		}
	}
}
