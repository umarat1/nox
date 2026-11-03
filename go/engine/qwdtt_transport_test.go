package engine

import (
	"testing"
	"time"
)

func TestQwTransportMemo(t *testing.T) {
	dir := t.TempDir()
	m := qwMemo(dir)
	now := time.Unix(5000, 0)
	m.now = func() time.Time { return now }
	if m.PreferTCP("1.2.3.4:58000") {
		t.Fatal("empty memo")
	}
	m.Note("1.2.3.4:58000", "tcp")
	if !m.PreferTCP("1.2.3.4:58000") || m.PreferTCP("5.6.7.8:58000") {
		t.Fatal("tcp not remembered per peer")
	}
	// persisted
	qwMemoMu.Lock()
	delete(qwMemos, dir)
	qwMemoMu.Unlock()
	m2 := qwMemo(dir)
	m2.now = m.now
	if !m2.PreferTCP("1.2.3.4:58000") {
		t.Fatal("not persisted")
	}
	now = now.Add(qwTCPMemoTTL + time.Minute)
	if m2.PreferTCP("1.2.3.4:58000") {
		t.Fatal("ttl not applied")
	}
	m2.Note("1.2.3.4:58000", "tcp")
	m2.Note("1.2.3.4:58000", "udp")
	if m2.PreferTCP("1.2.3.4:58000") {
		t.Fatal("udp switch must clear")
	}
}
