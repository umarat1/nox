package noxproto

import (
	"bytes"
	"io"
	"sync"
	"time"
)

// bufPipe is an in-memory stream with a size cap. Write blocks while the
// buffer is over the cap so a slow reader applies backpressure.
type bufPipe struct {
	mu     sync.Mutex
	cond   *sync.Cond
	b      bytes.Buffer
	max    int
	closed bool
}

func newBufPipe(max int) *bufPipe {
	p := &bufPipe{max: max}
	p.cond = sync.NewCond(&p.mu)
	return p
}

func (p *bufPipe) Write(d []byte) (int, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for p.max > 0 && p.b.Len() >= p.max && !p.closed {
		p.cond.Wait()
	}
	if p.closed {
		return 0, io.ErrClosedPipe
	}
	n, _ := p.b.Write(d)
	p.cond.Broadcast()
	return n, nil
}

func (p *bufPipe) Read(d []byte) (int, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for p.b.Len() == 0 && !p.closed {
		p.cond.Wait()
	}
	if p.b.Len() == 0 {
		return 0, io.EOF
	}
	n, _ := p.b.Read(d)
	p.cond.Broadcast()
	return n, nil
}

// take returns up to max bytes, waiting up to wait for the first byte.
func (p *bufPipe) take(max int, wait time.Duration) []byte {
	p.mu.Lock()
	defer p.mu.Unlock()
	deadline := time.Now().Add(wait)
	for p.b.Len() == 0 && !p.closed && time.Now().Before(deadline) {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			break
		}
		timer := time.AfterFunc(remaining, func() {
			p.mu.Lock()
			p.cond.Broadcast()
			p.mu.Unlock()
		})
		p.cond.Wait()
		timer.Stop()
	}
	if p.b.Len() == 0 {
		return nil
	}
	n := p.b.Len()
	if max > 0 && n > max {
		n = max
	}
	out := make([]byte, n)
	_, _ = p.b.Read(out)
	p.cond.Broadcast()
	return out
}

func (p *bufPipe) Close() error {
	p.mu.Lock()
	p.closed = true
	p.cond.Broadcast()
	p.mu.Unlock()
	return nil
}
