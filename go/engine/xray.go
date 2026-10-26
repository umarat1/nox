package engine

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"nox/core"
)

// xrayProc is a running Xray-core serving XHTTP servers on loopback SOCKS5 ports.
type xrayProc struct {
	cmd   *exec.Cmd
	cfg   string
	done  chan struct{}
	mu    sync.Mutex
	tail  []string
	ports []int
}

func (x *xrayProc) Stop() {
	if x == nil {
		return
	}
	if x.cmd.Process != nil {
		x.cmd.Process.Kill()
	}
	<-x.done
	os.Remove(x.cfg)
}

func (x *xrayProc) lastErr() string {
	x.mu.Lock()
	defer x.mu.Unlock()
	return strings.Join(x.tail, " | ")
}

// startXray runs Xray-core for the given "_xray" outbounds; ports[i] serves outbounds[i].
// Server domains are pre-resolved (public DNS / DoH first, fake IPs skipped) so Xray never
// depends on the system resolver (absent for plain binaries on Android).
func (a *App) startXray(name string, obs []json.RawMessage, pn pingNet) (*xrayProc, error) {
	var ents []core.XrayEntry
	var ports []int
	for _, ob := range obs {
		var w struct{ Server string }
		json.Unmarshal(ob, &w)
		p := freePort()
		ents = append(ents, core.XrayEntry{Outbound: ob, Port: p, IP: pn.resolveDirect(w.Server)})
		ports = append(ports, p)
	}
	b, err := core.XrayConfig(ents)
	if err != nil {
		return nil, err
	}
	dir := filepath.Join(a.dataDir, "xray")
	os.MkdirAll(dir, 0o700)
	cfg := filepath.Join(dir, name+".json")
	if err := os.WriteFile(cfg, b, 0o600); err != nil {
		return nil, err
	}
	cmd := command(a.bin("xray"), "run", "-c", cfg)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "XRAY_LOCATION_ASSET="+dir)
	hideWindow(cmd)
	pr, pw := io.Pipe()
	cmd.Stdout, cmd.Stderr = pw, pw
	if err := cmd.Start(); err != nil {
		os.Remove(cfg)
		return nil, fmt.Errorf("Xray: движок не найден: %w", err)
	}
	attachJob(cmd)
	x := &xrayProc{cmd: cmd, cfg: cfg, done: make(chan struct{}), ports: ports}
	go func() {
		sc := bufio.NewScanner(pr)
		for sc.Scan() {
			l := sc.Text()
			x.mu.Lock()
			x.tail = append(x.tail, l)
			if len(x.tail) > 4 {
				x.tail = x.tail[1:]
			}
			x.mu.Unlock()
			if name == "main" {
				a.log("[xray] " + l)
			}
		}
	}()
	go func() { cmd.Wait(); pw.Close(); close(x.done) }()
	// ready when every SOCKS port accepts
	deadline := time.Now().Add(8 * time.Second)
	for _, p := range ports {
		for {
			c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", p), 300*time.Millisecond)
			if err == nil {
				c.Close()
				break
			}
			select {
			case <-x.done:
				return nil, errors.New("Xray завершился: " + x.lastErr())
			default:
			}
			if time.Now().After(deadline) {
				x.Stop()
				return nil, errors.New("Xray не запустился: " + x.lastErr())
			}
			time.Sleep(60 * time.Millisecond)
		}
	}
	return x, nil
}

func socksOut(port int) map[string]any {
	return map[string]any{"type": "socks", "server": "127.0.0.1", "server_port": port, "version": "5"}
}
