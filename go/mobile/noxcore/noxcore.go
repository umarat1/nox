// Package noxcore is the Android binding of the Nox engine (gomobile AAR).
//
// The engine (subscriptions, ping, ordering, updates) and sing-box (libbox) run inside the
// app process. Kotlin implements Host: the VpnService side (TUN fd, protect, network
// monitor). Flutter talks to the engine through Call (same JSON-RPC methods as the Windows
// service over loopback IPC).
package noxcore

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"nox/engine"
	"nox/ipc"
)

// Host is implemented in Kotlin (NoxHost).
type Host interface {
	// StartService starts the foreground VpnService; returns once it is running.
	StartService(tun bool) error
	StopService()
	// OpenTun builds the VpnService interface from JSON options; returns the TUN fd.
	OpenTun(optionsJSON string) (int32, error)
	Protect(fd int32) bool
	StartNetMonitor()
	StopNetMonitor()
	// GetInterfaces returns JSON [{name,index,mtu,flags,type,addrs[],dns[],metered}].
	GetInterfaces() (string, error)
	InstallApk(path string) error
	// OnStatus: status changes for the notification / quick-settings tile.
	OnStatus(status string, server string)
}

var (
	mu   sync.Mutex
	app  *engine.App
	rpc  *ipc.Server
	host Host
)

// Init starts the engine once per process. dataDir: filesDir/nox; libDir:
// applicationInfo.nativeLibraryDir (libqwdtt.so); ruleDir: rule sets copied from assets.
func Init(dataDir, libDir, ruleDir string, h Host) error {
	mu.Lock()
	defer mu.Unlock()
	if app != nil {
		host = h
		return nil
	}
	host = h
	os.MkdirAll(dataDir, 0o755)
	if err := setupLibbox(filepath.Join(dataDir, "box")); err != nil {
		return err
	}
	engine.AndroidRuleDir = ruleDir
	engine.AndroidStartVpn = startVpn
	engine.AndroidStopVpn = stopVpn
	engine.AndroidTestCore = testCore
	engine.AndroidInstallApk = func(p string) error { return host.InstallApk(p) }
	setResolver()
	app = engine.NewApp(dataDir, libDir)
	rpc = ipc.New(app)
	app.Start()
	go statusLoop()
	return nil
}

type reply struct {
	R any    `json:"r,omitempty"`
	E string `json:"e,omitempty"`
}

// Call runs an engine method: args is a JSON array; returns {"r":…} or {"e":"…"}.
func Call(method, args string) string {
	mu.Lock()
	s := rpc
	mu.Unlock()
	if s == nil {
		return `{"e":"ядро не запущено"}`
	}
	var a []json.RawMessage
	if args != "" && json.Unmarshal([]byte(args), &a) != nil {
		return `{"e":"bad args"}`
	}
	r, err := s.Call(method, a)
	var out reply
	if err != nil {
		out.E = err.Error()
	} else {
		out.R = r
	}
	b, _ := json.Marshal(out)
	return string(b)
}

// SetDNS: system DNS server of the default network (LinkProperties), used for direct lookups.
func SetDNS(server string) {
	if net.ParseIP(server) != nil {
		mu.Lock()
		engine.AndroidDNS = server
		mu.Unlock()
	}
}

// VpnStopped is called by NoxVpnService when it goes down on its own (revoked by the
// system or another VPN app, killed). msg is shown to the user if non-empty.
func VpnStopped(msg string) {
	closeMain()
	engine.VpnStopped(msg)
}

// Version of the engine.
func Version() string { return engine.Version }

func statusLoop() {
	last := ""
	for range time.Tick(time.Second) {
		st := app.GetState()
		key := st.Status + "|" + st.Selected
		if key == last {
			continue
		}
		last = key
		name := ""
		for _, s := range st.Servers {
			if s.ID == st.Selected {
				name = s.Name
			}
		}
		mu.Lock()
		h := host
		mu.Unlock()
		if h != nil {
			h.OnStatus(st.Status, name)
		}
	}
}

// Go's pure resolver reads /etc/resolv.conf, which Android does not have.
func setResolver() {
	net.DefaultResolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
		mu.Lock()
		srv := engine.AndroidDNS
		mu.Unlock()
		d := net.Dialer{Timeout: 3 * time.Second}
		c, err := d.DialContext(ctx, network, net.JoinHostPort(srv, "53"))
		if err != nil && srv != "1.1.1.1" {
			c, err = d.DialContext(ctx, network, "1.1.1.1:53")
		}
		return c, err
	}}
}
