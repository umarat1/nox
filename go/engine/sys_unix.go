//go:build !windows && !darwin

package engine

import "os/exec"

func hideWindow(c *exec.Cmd)                 {}
func attachJob(c *exec.Cmd)                  {}
func gracefulStop(c *exec.Cmd)               { c.Process.Kill(); c.Wait() }
func setSystemProxy(on bool, port int) error { return nil }
func setAutostart(on bool) error             { return nil }
