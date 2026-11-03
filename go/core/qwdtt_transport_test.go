package core

import (
	"strings"
	"testing"
)

const qwBase = "qwdtt://config?peer=1.2.3.4:58000&hashes=h1,h2&pass=p&workers=16"

func hasArg(a []string, f string) bool {
	for _, x := range a {
		if x == f {
			return true
		}
	}
	return false
}

func TestQwdttTransportParam(t *testing.T) {
	cases := []struct {
		link      string
		auto, tcp bool
		transport string
	}{
		{qwBase, true, false, ""},
		{qwBase + "&turn_tcp=1", true, true, ""},
		{qwBase + "&transport=auto", true, false, "auto"},
		{qwBase + "&transport=tcp", false, true, "tcp"},
		{qwBase + "&turn=UDP&turn_tcp=1", false, false, "udp"},
	}
	for _, c := range cases {
		q, err := ParseQwdtt(c.link)
		if err != nil {
			t.Fatal(err)
		}
		if q.AutoTransport() != c.auto || q.TurnTCP != c.tcp || q.Transport != c.transport {
			t.Fatalf("%s: auto=%v tcp=%v tr=%q", c.link, q.AutoTransport(), q.TurnTCP, q.Transport)
		}
	}
}

func TestQwdttLaunchArgs(t *testing.T) {
	q, _ := ParseQwdtt(qwBase)
	if a := q.RelayArgs("d", "yandex"); hasArg(a, "-turn-auto") || hasArg(a, "-turn-tcp") {
		t.Fatalf("legacy args changed: %v", a)
	}
	a := q.LaunchArgs("d", "yandex", true, false)
	if !hasArg(a, "-turn-auto") || hasArg(a, "-turn-tcp") {
		t.Fatalf("auto udp: %v", a)
	}
	a = q.LaunchArgs("d", "yandex", true, true)
	if !hasArg(a, "-turn-auto") || !hasArg(a, "-turn-tcp") {
		t.Fatalf("auto learned tcp: %v", a)
	}
	p, _ := ParseQwdtt(qwBase + "&transport=udp")
	a = p.LaunchArgs("d", "yandex", true, true)
	if hasArg(a, "-turn-auto") || hasArg(a, "-turn-tcp") {
		t.Fatalf("pinned udp must ignore memo: %v", a)
	}
	if strings.Contains(strings.Join(a, " "), "transport") {
		t.Fatal("unexpected arg")
	}
}

func TestQwdttTransportLine(t *testing.T) {
	if to, why, ok := QwdttTransportLine("TRANSPORT|udp|tcp|data-stall"); !ok || to != "tcp" || why != "data-stall" {
		t.Fatal(to, why, ok)
	}
	for _, l := range []string{"", "TRANSPORT|udp", "TRANSPORT|udp|xx|r", "2026 [ТРАНСПОРТ] x"} {
		if _, _, ok := QwdttTransportLine(l); ok {
			t.Fatalf("accepted %q", l)
		}
	}
}
