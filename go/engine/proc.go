package engine

import (
	"io"
	"os/exec"
	"strings"
	"sync"
	"time"
)

// coreProc is a running sing-box: a child process on desktop, the in-process libbox
// service (driven by VpnService) on Android.
type coreProc interface {
	Wait() error
	Stop()
}

type execProc struct {
	c    *exec.Cmd
	done chan struct{}
	err  error
}

func newExecProc(c *exec.Cmd) *execProc {
	p := &execProc{c: c, done: make(chan struct{})}
	go func() {
		p.err = c.Wait()
		close(p.done)
	}()
	return p
}

func (p *execProc) Wait() error {
	<-p.done
	return p.err
}

func (p *execProc) Stop() {
	if p.c != nil && p.c.Process != nil {
		p.c.Process.Kill()
	}
	select {
	case <-p.done:
	case <-time.After(3 * time.Second):
	}
}

// startExecCore runs `sing-box run` as a child process (desktop).
func startExecCore(a *App, cfg string, out io.Writer) (*exec.Cmd, error) {
	cmd := exec.Command(a.bin("sing-box"), "run", "-c", cfg, "-D", a.dataDir, "--disable-color")
	hideWindow(cmd)
	cmd.Stdout, cmd.Stderr = out, out
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	attachJob(cmd)
	return cmd, nil
}

// syncBuf collects test-core output (written from another goroutine in-process on Android).
type syncBuf struct {
	mu sync.Mutex
	b  strings.Builder
}

func (s *syncBuf) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncBuf) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}
