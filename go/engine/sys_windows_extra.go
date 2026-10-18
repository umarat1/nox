//go:build windows

package engine

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
)

const exeExt = ".exe"

func osName() string               { return "windows" }
func ruleDir(binDir string) string { return binDir }

func startCore(a *App, cfg string, tun bool, out io.WriteCloser) (*exec.Cmd, error) {
	cmd := exec.Command(a.bin("sing-box"), "run", "-c", cfg, "-D", a.dataDir, "--disable-color")
	hideWindow(cmd)
	cmd.Stdout, cmd.Stderr = out, out
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	attachJob(cmd)
	return cmd, nil
}

func applyUpdate(a *App, u *UpdateInfo) error {
	path, err := a.download(u)
	if err != nil {
		return err
	}
	// signed installer verified in download(); it stops/replaces the service itself
	a.stopAll()
	// the installer closes Nox.exe; the restarted service brings the UI back (cmd/noxd relaunch)
	os.WriteFile(filepath.Join(a.dataDir, "relaunch-ui"), []byte("1"), 0o644)
	c := exec.Command(path, "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG="+filepath.Join(a.dataDir, "update.log"))
	hideWindow(c)
	return c.Start()
}
