package noxproto

import (
	"sync"
	"time"
)

// replayCache remembers client ephemeral public keys so a captured handshake
// cannot be played twice inside the acceptance window.
type replayCache struct {
	mu   sync.Mutex
	keys map[[32]byte]time.Time
}

func newReplay() *replayCache {
	return &replayCache{keys: map[[32]byte]time.Time{}}
}

func (c *replayCache) seen(k [32]byte) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	_, ok := c.keys[k]
	return ok
}

// add records k. It returns false if k was already present.
func (c *replayCache) add(k [32]byte, now time.Time) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.sweep(now)
	if _, ok := c.keys[k]; ok {
		return false
	}
	c.keys[k] = now
	return true
}

func (c *replayCache) sweep(now time.Time) {
	for k, t := range c.keys {
		if now.Sub(t) > replayRemember {
			delete(c.keys, k)
		}
	}
}
