//go:build windows

package main

import (
	"log"
	"os"
	"path/filepath"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// After a silent self-update the installer closes Nox.exe. The service (LocalSystem,
// session 0) restarts the UI in the active console session as the logged-on user.
// The marker is written by engine.applyUpdate just before it runs the installer.
func relaunchUIIfMarked(dir string) {
	marker := filepath.Join(dir, "relaunch-ui")
	if _, err := os.Stat(marker); err != nil {
		return
	}
	os.Remove(marker)
	exe, _ := os.Executable()
	ui := filepath.Join(filepath.Dir(filepath.Dir(exe)), "Nox.exe")
	if _, err := os.Stat(ui); err != nil {
		return
	}
	go func() {
		for i := 0; i < 30; i++ { // user may not be logged on yet right after boot
			if err := launchAsConsoleUser(ui); err == nil {
				return
			} else if i == 29 {
				log.Printf("relaunch UI: %v", err)
			}
			time.Sleep(2 * time.Second)
		}
	}()
}

func launchAsConsoleUser(path string) error {
	sid := windows.WTSGetActiveConsoleSessionId()
	if sid == 0xFFFFFFFF {
		return windows.ERROR_NO_SUCH_LOGON_SESSION
	}
	var tok windows.Token
	if err := windows.WTSQueryUserToken(sid, &tok); err != nil {
		return err
	}
	defer tok.Close()
	var env *uint16
	if windows.CreateEnvironmentBlock(&env, tok, false) == nil {
		defer windows.DestroyEnvironmentBlock(env)
	}
	cmd, _ := windows.UTF16PtrFromString(`"` + path + `"`)
	dir, _ := windows.UTF16PtrFromString(filepath.Dir(path))
	desk, _ := windows.UTF16PtrFromString(`winsta0\default`)
	si := windows.StartupInfo{Cb: uint32(unsafe.Sizeof(windows.StartupInfo{})), Desktop: desk}
	var pi windows.ProcessInformation
	err := windows.CreateProcessAsUser(tok, nil, cmd, nil, nil, false,
		windows.CREATE_UNICODE_ENVIRONMENT|windows.CREATE_NEW_PROCESS_GROUP, env, dir, &si, &pi)
	if err != nil {
		return err
	}
	windows.CloseHandle(pi.Thread)
	windows.CloseHandle(pi.Process)
	return nil
}
