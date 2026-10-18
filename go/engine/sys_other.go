//go:build !windows

package engine

import (
	"io"
	"os/exec"
)

func hideWindow(c *exec.Cmd)                 {}
func attachJob(c *exec.Cmd)                  {}
func gracefulStop(c *exec.Cmd)               { c.Process.Kill(); c.Wait() }
func setSystemProxy(on bool, port int) error { return nil }
func setAutostart(on bool) error             { return nil }

const exeExt = ".exe" // tests on Linux use symlinked sing-box.exe

func osName() string                          { return "linux" }
func ruleDir(binDir string) string            { return binDir }
func applyUpdate(a *App, u *UpdateInfo) error { return nil }
func startCore(a *App, cfg string, tun bool, out io.WriteCloser) (*exec.Cmd, error) {
	cmd := exec.Command(a.bin("sing-box"), "run", "-c", cfg, "-D", a.dataDir, "--disable-color")
	cmd.Stdout, cmd.Stderr = out, out
	return cmd, cmd.Start()
}
