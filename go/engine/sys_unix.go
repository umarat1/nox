//go:build !windows && !darwin

package engine

import (
	"os/exec"
	"time"
)

func hideWindow(c *exec.Cmd) {}
func attachJob(c *exec.Cmd)  {}
func gracefulStop(c *exec.Cmd) {
	if c == nil || c.Process == nil {
		return
	}
	c.Process.Kill()
	done := make(chan struct{})
	go func() { c.Process.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
	}
}
func setSystemProxy(on bool, port int) error { return nil }
func setAutostart(on bool) error             { return nil }
