package engine

import (
	"testing"

	"nox/core"
)

func TestPathMemoryPrefersWorkedType(t *testing.T) {
	a := &App{dataDir: t.TempDir()}
	a.markPath("NOX", true)
	all := []core.Server{
		{ID: "1", Type: "VLESS", Ping: 10, Name: "a"},
		{ID: "2", Type: "NOX", Ping: 40, Name: "b"},
		{ID: "3", Type: "Hysteria2", Ping: 5, Name: "c"},
	}
	n := a.pickNext(all, all[0])
	if n == nil || n.ID != "2" {
		t.Fatalf("got %+v", n)
	}
	a.markPath("NOX", false)
	n = a.pickNext(all, all[0])
	if n == nil || n.Type == "NOX" {
		t.Fatalf("after failure got %+v", n)
	}
}
