//go:build windows

package engine

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
)

func osName() string               { return "windows" }
func ruleDir(binDir string) string { return binDir }

func binPath(dir, n string) string { return filepath.Join(dir, n+".exe") }

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

func applyUpdate(a *App, u *UpdateInfo) error {
	path, err := a.download(u)
	if err != nil {
		return err
	}
	return installUpdate(a, path)
}

func installUpdate(a *App, path string) error {
	// signed installer verified in download(); it stops/replaces the service itself
	a.stopAll()
	// the installer closes Nox.exe; the restarted service brings the UI back (cmd/noxd relaunch)
	os.WriteFile(filepath.Join(a.dataDir, "relaunch-ui"), []byte("1"), 0o644)
	c := exec.Command(path, "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG="+filepath.Join(a.dataDir, "update.log"))
	hideWindow(c)
	return c.Start()
}
