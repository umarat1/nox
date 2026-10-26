package noxproto

import (
	"encoding/json"
	"os"
	"sync"
	"time"
)

// Memory remembers which carrier worked on a given network, so the next
// connect tries that one first. The file is optional; a nil path keeps the
// memory in process only.
type Memory struct {
	path string
	mu   sync.Mutex
	nets map[string]memRec
}

type memRec struct {
	Carrier string `json:"carrier"`
	OK      bool   `json:"ok"`
	Fail    int    `json:"fail"`
	Unix    int64  `json:"unix"`
}

type memFile struct {
	Nets map[string]memRec `json:"nets"`
}

func OpenMemory(path string) *Memory {
	m := &Memory{path: path, nets: map[string]memRec{}}
	if path == "" {
		return m
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return m
	}
	var f memFile
	if json.Unmarshal(b, &f) == nil && f.Nets != nil {
		m.nets = f.Nets
	}
	return m
}

// Order puts the last successful carrier first.
func (m *Memory) Order(network string, carriers []string) []string {
	if m == nil || len(carriers) == 0 {
		return carriers
	}
	m.mu.Lock()
	rec := m.nets[network]
	m.mu.Unlock()
	if !rec.OK || rec.Carrier == "" {
		return append([]string(nil), carriers...)
	}
	out := make([]string, 0, len(carriers))
	for _, c := range carriers {
		if c == rec.Carrier {
			out = append([]string{c}, out...)
			continue
		}
		out = append(out, c)
	}
	if len(out) == 0 || out[0] != rec.Carrier {
		return append([]string(nil), carriers...)
	}
	return out
}

func (m *Memory) Success(network, carrier string) { m.store(network, carrier, true) }
func (m *Memory) Fail(network, carrier string)    { m.store(network, carrier, false) }

func (m *Memory) store(network, carrier string, ok bool) {
	if m == nil || network == "" || carrier == "" {
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	rec := m.nets[network]
	rec.Unix = time.Now().Unix()
	if ok {
		rec.Carrier = carrier
		rec.OK = true
		rec.Fail = 0
	} else {
		rec.Fail++
		if !rec.OK {
			rec.Carrier = carrier
		}
	}
	m.nets[network] = rec
	if m.path == "" {
		return
	}
	b, err := json.Marshal(memFile{Nets: m.nets})
	if err != nil {
		return
	}
	tmp := m.path + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		_ = os.Rename(tmp, m.path)
	}
}
