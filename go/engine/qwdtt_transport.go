package engine

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"
)

// qwdtt transport memory: when the bundled qwdtt (patched, -turn-auto) had
// to switch a server to TURN-over-TCP because UDP stopped passing data
// (typical for MTS and other mobile carriers), the next connect to that
// server starts on TCP right away instead of re-learning it. qwdtt can
// still switch back to UDP by itself. Entries expire after qwTCPMemoTTL so
// a network change gets a fresh UDP attempt.

const qwTCPMemoTTL = 12 * time.Hour

// qwdttAutoSupported: only the Android libqwdtt is built from the patched
// source (scripts/build-libqwdtt.sh); the Windows binary has no -turn-auto.
func qwdttAutoSupported() bool { return runtime.GOOS == "android" }

type qwTransportMemo struct {
	mu   sync.Mutex
	path string
	m    map[string]int64 // peer -> unix seconds when TCP was learned
	now  func() time.Time
}

var (
	qwMemoMu sync.Mutex
	qwMemos  = map[string]*qwTransportMemo{}
)

func qwMemo(dataDir string) *qwTransportMemo {
	qwMemoMu.Lock()
	defer qwMemoMu.Unlock()
	if m := qwMemos[dataDir]; m != nil {
		return m
	}
	m := &qwTransportMemo{path: filepath.Join(dataDir, "qwdtt", "transport.json"), m: map[string]int64{}, now: time.Now}
	if b, err := os.ReadFile(m.path); err == nil {
		json.Unmarshal(b, &m.m)
	}
	qwMemos[dataDir] = m
	return m
}

func (m *qwTransportMemo) PreferTCP(peer string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	t, ok := m.m[peer]
	if !ok {
		return false
	}
	if m.now().Sub(time.Unix(t, 0)) > qwTCPMemoTTL {
		delete(m.m, peer)
		m.saveLocked()
		return false
	}
	return true
}

func (m *qwTransportMemo) Note(peer, to string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if to == "tcp" {
		m.m[peer] = m.now().Unix()
	} else {
		delete(m.m, peer)
	}
	m.saveLocked()
}

func (m *qwTransportMemo) saveLocked() {
	b, _ := json.Marshal(m.m)
	os.MkdirAll(filepath.Dir(m.path), 0o700)
	tmp := m.path + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		os.Rename(tmp, m.path)
	}
}
