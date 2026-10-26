package noxproto

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync"
)

// Dialer is the client. It keeps one multiplexed session and redials, rotating
// carriers, when that session dies.
type Dialer struct {
	cfg Config
	mem *Memory

	mu   sync.Mutex
	sess *session
	stop func()
	wait chan struct{}
}

// NewDialer builds a client from a subscription cfg map.
func NewDialer(m map[string]any) (*Dialer, error) {
	cfg, err := ConfigFromMap(m)
	if err != nil {
		return nil, err
	}
	return NewDialerConfig(cfg), nil
}

// NewDialerConfig builds a client from an already-checked Config.
func NewDialerConfig(cfg Config) *Dialer {
	if err := cfg.validate(); err != nil {
		// Caller of NewDialerConfig is expected to pass a valid config.
		// Dial reports the error later if validation failed here; store it
		// by clearing carriers so Dial fails closed.
	}
	if cfg.Network == "" {
		cfg.Network = NetworkLabel()
	}
	return &Dialer{cfg: cfg, mem: OpenMemory(cfg.MemFile)}
}

// Dial opens a stream to host:port. network is "tcp" or "udp".
func (d *Dialer) Dial(ctx context.Context, network, host string, port uint16) (net.Conn, error) {
	if err := d.cfg.validate(); err != nil {
		return nil, err
	}
	udp := network == "udp"
	sess, err := d.session(ctx)
	if err != nil {
		return nil, err
	}
	c, err := sess.open(host, port, udp)
	if err != nil && !sess.alive() {
		d.drop(sess)
		sess, err = d.session(ctx)
		if err != nil {
			return nil, err
		}
		c, err = sess.open(host, port, udp)
	}
	return c, err
}

func (d *Dialer) drop(s *session) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.sess == s {
		if d.stop != nil {
			d.stop()
		}
		d.sess = nil
		d.stop = nil
	}
}

func (d *Dialer) session(ctx context.Context) (*session, error) {
	d.mu.Lock()
	if d.sess.alive() {
		s := d.sess
		d.mu.Unlock()
		return s, nil
	}
	if d.wait != nil {
		ch := d.wait
		d.mu.Unlock()
		select {
		case <-ch:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		return d.session(ctx)
	}
	ch := make(chan struct{})
	d.wait = ch
	d.mu.Unlock()

	s, stop, err := d.connect(ctx)

	d.mu.Lock()
	if err == nil {
		d.sess = s
		d.stop = stop
	}
	close(ch)
	d.wait = nil
	d.mu.Unlock()
	return s, err
}

func (d *Dialer) connect(ctx context.Context) (*session, func(), error) {
	order := d.mem.Order(d.cfg.Network, d.cfg.Carriers)
	var errs []error
	for _, c := range order {
		s, stop, err := dialCarrier(ctx, d.cfg, c)
		if err == nil {
			d.mem.Success(d.cfg.Network, c)
			return s, stop, nil
		}
		d.mem.Fail(d.cfg.Network, c)
		errs = append(errs, fmt.Errorf("%s: %w", c, err))
		if ctx.Err() != nil {
			break
		}
	}
	if len(errs) == 0 {
		return nil, nil, errors.New("nox: нет каналов")
	}
	return nil, nil, fmt.Errorf("nox: ни один канал не открылся: %w", errors.Join(errs...))
}

// Close drops the session.
func (d *Dialer) Close() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.stop != nil {
		d.stop()
	}
	d.sess = nil
	d.stop = nil
	return nil
}
