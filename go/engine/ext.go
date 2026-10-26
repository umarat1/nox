package engine

import (
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"

	"nox/extra"
	"nox/noxproto"
)

// extProc: one running in-process/extra protocol behind 127.0.0.1:port (SOCKS5).
type extProc struct {
	port int
	stop func()
}

func (e *extProc) Stop() {
	if e != nil && e.stop != nil {
		e.stop()
	}
}

func (a *App) startExt(raw []byte) (*extProc, error) {
	var w struct {
		Kind string         `json:"kind"`
		Cfg  map[string]any `json:"cfg"`
	}
	if err := json.Unmarshal(raw, &w); err != nil {
		return nil, err
	}
	if w.Kind == "naive" {
		return a.startNaive(w.Cfg)
	}
	if w.Kind == "nox" {
		if w.Cfg == nil {
			w.Cfg = map[string]any{}
		}
		if w.Cfg["memfile"] == nil || w.Cfg["memfile"] == "" {
			w.Cfg["memfile"] = filepath.Join(a.dataDir, "nox-paths.json")
		}
		if w.Cfg["network"] == nil || w.Cfg["network"] == "" {
			w.Cfg["network"] = noxproto.NetworkLabel()
		}
		b, err := json.Marshal(map[string]any{"kind": w.Kind, "cfg": w.Cfg})
		if err != nil {
			return nil, err
		}
		raw = b
	}
	l, err := extra.Start(raw)
	if err != nil {
		return nil, err
	}
	return &extProc{port: l.Port, stop: l.Stop}, nil
}

// startNaive runs the NaiveProxy client (libnaive.so / naive.exe) as a local SOCKS5.
func (a *App) startNaive(cfg map[string]any) (*extProc, error) {
	str := func(k string) string { s, _ := cfg[k].(string); return s }
	host, ip := str("host"), str("ip")
	port := freePort()
	u := url.URL{Scheme: str("scheme"), Host: net.JoinHostPort(host, strconv.Itoa(int(num(cfg["port"]))))}
	if str("user") != "" {
		u.User = url.UserPassword(str("user"), str("pass"))
	}
	args := []string{"--listen=socks://127.0.0.1:" + strconv.Itoa(port), "--proxy=" + u.String()}
	if ip != "" {
		args = append(args, "--host-resolver-rules=MAP "+host+" "+ip)
	}
	cmd := exec.Command(a.bin("naive"), args...)
	hideWindow(cmd)
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("Naive: движок не найден: %w", err)
	}
	attachJob(cmd)
	done := make(chan struct{})
	go func() { cmd.Wait(); close(done) }()
	stop := func() { cmd.Process.Kill(); <-done }
	for i := 0; i < 50; i++ {
		select {
		case <-done:
			return nil, fmt.Errorf("Naive завершился при запуске")
		default:
		}
		if c, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 100*time.Millisecond); err == nil {
			c.Close()
			return &extProc{port: port, stop: stop}, nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	stop()
	return nil, fmt.Errorf("Naive: не запустился")
}

func num(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case int:
		return float64(x)
	}
	return 0
}
