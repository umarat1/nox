//go:build !windows && !android

package engine

import (
	"io"
	"path/filepath"
)

// tests on Linux use symlinked sing-box.exe
func binPath(dir, n string) string            { return filepath.Join(dir, n+".exe") }
func osName() string                          { return "linux" }
func ruleDir(binDir string) string            { return binDir }
func applyUpdate(a *App, u *UpdateInfo) error { return nil }
func startCore(a *App, cfg string, tun bool, out io.WriteCloser) (coreProc, error) {
	c, err := startExecCore(a, cfg, out)
	if err != nil {
		return nil, err
	}
	return execProc{c}, nil
}
func startTestCore(a *App, cfg string, out io.Writer) (coreProc, error) {
	c, err := startExecCore(a, cfg, out)
	if err != nil {
		return nil, err
	}
	return execProc{c}, nil
}
