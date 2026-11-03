package engine

// Live check (2.3.3 «МТС прокси»): NaiveProxy and mieru chain through an HTTP proxy at
// 192.168.192.192:80. Runs only with NOX_E2E_SUB=<file with share links> and a local
// HTTP proxy bound on 192.168.192.192:80; NOX_E2E_BIN = dir with the naive binary.

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"testing"
	"time"

	"nox/core"
)

func socksGet204(port int) (int, error) {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 5*time.Second)
	if err != nil {
		return 0, err
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(20 * time.Second))
	c.Write([]byte{5, 1, 0})
	b := make([]byte, 2)
	if _, err := io.ReadFull(c, b); err != nil {
		return 0, err
	}
	host := "www.gstatic.com"
	req := append([]byte{5, 1, 0, 3, byte(len(host))}, host...)
	req = append(req, 0, 80)
	c.Write(req)
	r := make([]byte, 10)
	if _, err := io.ReadFull(c, r); err != nil || r[1] != 0 {
		return 0, fmt.Errorf("socks connect: %v %v", err, r)
	}
	fmt.Fprintf(c, "GET /generate_204 HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", host)
	line := make([]byte, 12)
	if _, err := io.ReadFull(c, line); err != nil {
		return 0, err
	}
	var code int
	fmt.Sscanf(string(line[9:12]), "%d", &code)
	return code, nil
}

func TestMtsExtLive233(t *testing.T) {
	sub := os.Getenv("NOX_E2E_SUB")
	if sub == "" {
		t.Skip("NOX_E2E_SUB not set")
	}
	b, _ := os.ReadFile(sub)
	a := &App{binDir: os.Getenv("NOX_E2E_BIN")}
	n := 0
	for _, l := range strings.Split(string(b), "\n") {
		sv, err := core.ParseLink(strings.TrimSpace(l))
		if err != nil || !core.IsExt(sv.Outbound) {
			continue
		}
		var w struct {
			Kind string
			Cfg  map[string]any
		}
		json.Unmarshal(sv.Outbound, &w)
		viaMts := os.Getenv("NOX_E2E_MTS") != "0"
		if r := mtsUnsupported(sv); r != "" && viaMts {
			t.Logf("%-8s %-40s МТС: blocked (%s)", w.Kind, sv.Name, r)
			continue
		}
		e, err := a.startExt(sv.Outbound, viaMts)
		if err != nil {
			t.Errorf("%s: start: %v", sv.Name, err)
			continue
		}
		_, cancel := context.WithCancel(context.Background())
		code, err := socksGet204(e.port)
		cancel()
		e.stop()
		t.Logf("%-8s %-40s mts=%v: %d %v", w.Kind, sv.Name, viaMts, code, err)
		if code != 204 {
			t.Errorf("%s: via MTS proxy got %d %v", sv.Name, code, err)
		}
		n++
	}
	if n == 0 {
		t.Fatal("no MTS-capable _ext servers")
	}
}
