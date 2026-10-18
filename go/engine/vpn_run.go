package engine

// Full-tunnel engine that bypasses sing-box: SSTP (Windows built-in RAS client via PowerShell
// Add-VpnConnection + rasdial; sstpc on Linux). No OpenVPN in Nox 1.0.

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"nox/core"
)

const sstpEntry = "Nox SSTP"

func (a *App) connectFullTunnel(ctx context.Context, srv core.Server) error {
	s, err := core.SSTPFrom(srv.Outbound)
	if err != nil {
		return errors.New("неизвестный тип туннеля")
	}
	if runtime.GOOS == "android" {
		return a.startSSTPAndroid(ctx, srv, s)
	}
	return a.startSSTP(ctx, srv, s)
}

func (a *App) markConnected(name string) {
	a.mu.Lock()
	a.status = "connected"
	a.since = time.Now().Unix()
	a.mu.Unlock()
	a.log("подключено: " + name)
}

func psQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }

func (a *App) startSSTP(ctx context.Context, srv core.Server, s core.SSTP) error {
	if runtime.GOOS != "windows" {
		return a.startSSTPC(ctx, srv, s)
	}
	addr := s.Server
	if s.Port != 0 && s.Port != 443 {
		addr = fmt.Sprintf("%s:%d", s.Server, s.Port) // RAS accepts host:port for SSTP
	}
	ps := fmt.Sprintf("Remove-VpnConnection -Name %s -Force -ErrorAction SilentlyContinue; "+
		"Add-VpnConnection -Name %s -ServerAddress %s -TunnelType Sstp -EncryptionLevel Required "+
		"-AuthenticationMethod MSChapv2 -SplitTunneling:$false -RememberCredential:$false -Force",
		psQuote(sstpEntry), psQuote(sstpEntry), psQuote(addr))
	c := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", ps)
	hideWindow(c)
	if out, err := c.CombinedOutput(); err != nil {
		return fmt.Errorf("SSTP: не удалось создать подключение: %v %s", err, lastLines(string(out), 2))
	}
	d := exec.CommandContext(ctx, "rasdial", sstpEntry, s.User, s.Password)
	hideWindow(d)
	out, err := d.CombinedOutput()
	if err != nil {
		return fmt.Errorf("SSTP: rasdial: %v %s", err, lastLines(string(out), 2))
	}
	a.mu.Lock()
	a.sstpUp = true
	a.mu.Unlock()
	a.markConnected(srv.Name)
	return nil
}

// Linux/macOS: sstpc (sstp-client) + pppd.
func (a *App) startSSTPC(ctx context.Context, srv core.Server, s core.SSTP) error {
	args := []string{"--cert-warn", "--log-stderr", "--user", s.User, "--password", s.Password,
		fmt.Sprintf("%s:%d", s.Server, s.Port), "usepeerdns", "require-mschap-v2", "noauth", "defaultroute", "replacedefaultroute"}
	cmd := exec.Command("sstpc", args...)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("SSTP: sstpc не найден: %w", err)
	}
	a.mu.Lock()
	a.tun = cmd
	a.mu.Unlock()
	a.markConnected(srv.Name)
	return nil
}

func (a *App) stopFullTunnel() {
	if runtime.GOOS == "android" {
		a.stopSSTPAndroid()
		return
	}
	a.mu.Lock()
	tun, sstp := a.tun, a.sstpUp
	a.tun, a.sstpUp = nil, false
	a.mu.Unlock()
	if tun != nil && tun.Process != nil {
		gracefulStop(tun)
	}
	if sstp {
		c := exec.Command("rasdial", sstpEntry, "/disconnect")
		hideWindow(c)
		c.Run()
	}
}
