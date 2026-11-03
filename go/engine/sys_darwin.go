//go:build darwin

package engine

import (
	"fmt"
	"os/exec"
	"time"
	"strings"
)

func hideWindow(c *exec.Cmd)     {}
func attachJob(c *exec.Cmd)      {}
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
func setAutostart(on bool) error { return nil }

// macOS proxy mode: point every network service (Wi-Fi, Ethernet, …) at the local
// HTTP+SOCKS inbound. networksetup usually needs admin rights; on refusal we ask once
// through the standard macOS password dialog.
func setSystemProxy(on bool, port int) error {
	out, err := exec.Command("/usr/sbin/networksetup", "-listallnetworkservices").Output()
	if err != nil {
		return err
	}
	var cmds []string
	for _, l := range strings.Split(string(out), "\n") {
		l = strings.TrimSpace(l)
		if l == "" || strings.HasPrefix(l, "An asterisk") || strings.HasPrefix(l, "*") {
			continue
		}
		q := "'" + strings.ReplaceAll(l, "'", `'\''`) + "'"
		if on {
			p := fmt.Sprint(port)
			cmds = append(cmds,
				"networksetup -setwebproxy "+q+" 127.0.0.1 "+p,
				"networksetup -setsecurewebproxy "+q+" 127.0.0.1 "+p,
				"networksetup -setsocksfirewallproxy "+q+" 127.0.0.1 "+p,
				"networksetup -setproxybypassdomains "+q+" localhost 127.0.0.1 '*.local' 169.254/16")
		} else {
			cmds = append(cmds,
				"networksetup -setwebproxystate "+q+" off",
				"networksetup -setsecurewebproxystate "+q+" off",
				"networksetup -setsocksfirewallproxystate "+q+" off")
		}
	}
	if len(cmds) == 0 {
		return nil
	}
	script := strings.Join(cmds, " && ")
	if err := exec.Command("/bin/sh", "-c", script).Run(); err == nil {
		return nil
	}
	as := `do shell script "` + strings.ReplaceAll(strings.ReplaceAll(script, `\`, `\\`), `"`, `\"`) + `" with administrator privileges`
	if b, err := exec.Command("/usr/bin/osascript", "-e", as).CombinedOutput(); err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(b)))
	}
	return nil
}
