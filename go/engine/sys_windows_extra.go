//go:build windows

package engine

import (
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

// detectPackaged (2.4.0): true when noxd runs from an MSIX package (packaged service).
// GetCurrentPackageFullName fails with APPMODEL_ERROR_NO_PACKAGE (15700) outside a package;
// the WindowsApps install path is the fallback for older systems.
func detectPackaged() bool {
	if p := syscall.NewLazyDLL("kernel32.dll").NewProc("GetCurrentPackageFullName"); p.Find() == nil {
		var n uint32
		r, _, _ := p.Call(uintptr(unsafe.Pointer(&n)), 0)
		if r == 122 { // ERROR_INSUFFICIENT_BUFFER: there is a package name
			return true
		}
		if r == 15700 {
			return false
		}
	}
	exe, _ := os.Executable()
	return strings.Contains(strings.ToLower(exe), `\windowsapps\`)
}

func init() { Packaged = detectPackaged() }

var errPackaged = errors.New("версия MSIX обновляется через Microsoft App Installer (при запуске приложения)")

func osName() string               { return "windows" }
func ruleDir(binDir string) string { return binDir }

func binPath(dir, n string) string { return filepath.Join(dir, n+".exe") }

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

func applyUpdate(a *App, u *UpdateInfo) error {
	if Packaged {
		return errPackaged
	}
	path, err := a.download(u)
	if err != nil {
		return err
	}
	return installUpdate(a, path)
}

var installHook func(string) error

func installUpdate(a *App, path string) error {
	if installHook != nil {
		return installHook(path)
	}
	if Packaged {
		// an Inno setup would install a second, unpackaged copy next to the MSIX one
		return errPackaged
	}
	// signed installer verified in download(); it stops/replaces the service itself
	a.stopAll()
	// the installer closes Nox.exe; the restarted service brings the UI back (cmd/noxd relaunch)
	os.WriteFile(filepath.Join(a.dataDir, "relaunch-ui"), []byte("1"), 0o644)
	c := exec.Command(path, "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG="+filepath.Join(a.dataDir, "update.log"))
	hideWindow(c)
	return c.Start()
}
