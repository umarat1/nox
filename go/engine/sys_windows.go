//go:build windows

package engine

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

var job windows.Handle

func init() {
	h, err := windows.CreateJobObject(nil, nil)
	if err != nil {
		return
	}
	info := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	info.BasicLimitInformation.LimitFlags = windows.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	if _, err := windows.SetInformationJobObject(h, windows.JobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&info)), uint32(unsafe.Sizeof(info))); err == nil {
		job = h
	}
}

func hideWindow(c *exec.Cmd) {
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
}

// attachJob makes children die with the app (no orphaned TUN core after a crash).
func attachJob(c *exec.Cmd) {
	if job == 0 || c.Process == nil {
		return
	}
	ph, err := windows.OpenProcess(windows.PROCESS_SET_QUOTA|windows.PROCESS_TERMINATE, false, uint32(c.Process.Pid))
	if err != nil {
		return
	}
	windows.AssignProcessToJobObject(job, ph)
	windows.CloseHandle(ph)
}

func gracefulStop(c *exec.Cmd) {
	c.Process.Kill()
	done := make(chan struct{})
	go func() { c.Process.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
	}
}

var wininet = windows.NewLazySystemDLL("wininet.dll")

func refreshProxy() {
	p := wininet.NewProc("InternetSetOptionW")
	p.Call(0, 39, 0, 0)
	p.Call(0, 37, 0, 0)
}

func setSystemProxy(on bool, port int) error {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Internet Settings`, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if on {
		k.SetStringValue("ProxyServer", fmt.Sprintf("127.0.0.1:%d", port))
		k.SetStringValue("ProxyOverride", "localhost;127.*;10.*;172.16.*;192.168.*;<local>")
		k.SetDWordValue("ProxyEnable", 1)
	} else {
		k.SetDWordValue("ProxyEnable", 0)
	}
	refreshProxy()
	return nil
}

func setAutostart(on bool) error {
	exe, _ := os.Executable()
	var c *exec.Cmd
	// the old VPS app used the task name "VPS"; two clients at logon would fight over TUN
	legacy := exec.Command("schtasks", "/Delete", "/F", "/TN", "VPS")
	hideWindow(legacy)
	legacy.Run()
	if on {
		c = exec.Command("schtasks", "/Create", "/F", "/TN", "Nox", "/SC", "ONLOGON", "/RL", "HIGHEST", "/TR", `"`+exe+`"`)
	} else {
		c = exec.Command("schtasks", "/Delete", "/F", "/TN", "Nox")
	}
	hideWindow(c)
	out, err := c.CombinedOutput()
	if err != nil && on {
		return fmt.Errorf("%v %s", err, out)
	}
	return nil
}
