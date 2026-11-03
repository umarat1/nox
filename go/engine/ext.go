package engine

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"
	"time"

	"nox/core"
	"nox/extra"
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

// startExt runs an _ext protocol behind a loopback SOCKS5. mts=true (2.3.3 «МТС прокси»)
// chains its upstream dials through the MTS HTTP proxy: NaiveProxy via a proxy chain
// (--proxy=http://mts,https://server), mieru via a CONNECT dialer inside mihomo.
func (a *App) startExt(raw []byte, mts ...bool) (*extProc, error) {
	viaMts := len(mts) > 0 && mts[0]
	var w struct {
		Kind string         `json:"kind"`
		Cfg  map[string]any `json:"cfg"`
	}
	if err := json.Unmarshal(raw, &w); err != nil {
		return nil, err
	}
	if w.Kind == "naive" {
		if viaMts {
			w.Cfg = withKey(w.Cfg, "_mts", true)
		}
		return a.startNaive(w.Cfg)
	}
	if viaMts {
		if r := extMtsBlocked(w.Kind, w.Cfg); r != "" {
			return nil, errors.New("МТС прокси: " + r)
		}
		var m map[string]any
		json.Unmarshal(raw, &m)
		m["cfg"] = withKey(w.Cfg, extra.ViaKey, net.JoinHostPort(core.MtsProxyHost, strconv.Itoa(core.MtsProxyPort)))
		raw, _ = json.Marshal(m)
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
	chain := u.String()
	if v, _ := cfg["_mts"].(bool); v {
		if u.Scheme == "quic" {
			return nil, errors.New("МТС прокси: NaiveProxy QUIC (UDP) не идёт через HTTP-прокси МТС")
		}
		chain = core.MtsProxyURL() + "," + chain // naive proxy chain: MTS HTTP proxy first
	}
	args := []string{"--listen=socks://127.0.0.1:" + strconv.Itoa(port), "--proxy=" + chain}
	if ip != "" {
		args = append(args, "--host-resolver-rules=MAP "+host+" "+ip)
	}
	cmd := command(a.bin("naive"), args...)
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

func withKey(cfg map[string]any, k string, v any) map[string]any {
	c := make(map[string]any, len(cfg)+1)
	for a, b := range cfg {
		c[a] = b
	}
	c[k] = v
	return c
}

// extMtsBlocked: "" when an _ext protocol can run through the MTS HTTP proxy (TCP only).
func extMtsBlocked(kind string, cfg map[string]any) string {
	t, _ := cfg["type"].(string)
	switch {
	case kind == "naive":
		if s, _ := cfg["scheme"].(string); s == "quic" {
			return "NaiveProxy QUIC (UDP) не идёт через HTTP-прокси МТС"
		}
		return ""
	case kind == "mihomo" && t == "mieru":
		if tr, _ := cfg["transport"].(string); strings.EqualFold(tr, "UDP") {
			return "mieru по UDP не идёт через HTTP-прокси МТС"
		}
		return ""
	}
	if t == "" {
		t = kind
	}
	return t + " (внешнее ядро) не умеет цепочку через HTTP-прокси МТС"
}
