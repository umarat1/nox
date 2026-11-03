//go:build !windows && !android

package engine

import (
	"io"
	"os/exec"
	"path/filepath"
	"runtime"
)

// tests on Linux use symlinked sing-box.exe
func binPath(dir, n string) string {
	if runtime.GOOS == "darwin" {
		return filepath.Join(dir, n) // macOS bundle: Nox.app/Contents/Resources/core/<n>
	}
	return filepath.Join(dir, n+".exe")
}

// osName: "macos" on darwin (2.1.5: it used to say "linux", so Macs read the
// non-existent nox2-linux channel and were never offered an update).
func osName() string {
	if runtime.GOOS == "darwin" {
		return "macos"
	}
	return "linux"
}
func ruleDir(binDir string) string            { return binDir }
func applyUpdate(a *App, u *UpdateInfo) error { return nil }

// installUpdate: tests replace it via installHook.
func installUpdate(a *App, path string) error {
	if installHook != nil {
		return installHook(path)
	}
	if runtime.GOOS == "darwin" {
		// verified DMG: Finder mounts it with Nox.app and the Applications link
		return exec.Command("open", path).Start()
	}
	return nil
}

var installHook func(string) error

func startCore(a *App, cfg string, tun bool, out io.WriteCloser) (coreProc, error) {
	c, err := startExecCore(a, cfg, out)
	if err != nil {
		return nil, err
	}
	return newExecProc(c), nil
}
func startTestCore(a *App, cfg string, out io.Writer) (coreProc, error) {
	c, err := startExecCore(a, cfg, out)
	if err != nil {
		return nil, err
	}
	return newExecProc(c), nil
}
