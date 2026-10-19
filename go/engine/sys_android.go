//go:build android

package engine

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"
)

// Android glue. The engine runs inside the app process (gomobile AAR, package nox/mobile).
// sing-box itself is embedded: the main tunnel goes through libbox driven by the Kotlin
// VpnService, URL-test pings through a second in-process box (no TUN). The mobile package
// fills these hooks in.
var (
	// AndroidStartVpn starts the foreground VpnService with the given sing-box config and
	// returns once libbox is running (or failed).
	AndroidStartVpn func(cfgPath string, tun bool) error
	AndroidStopVpn  func()
	// AndroidTestCore runs a non-TUN sing-box in process; stop() shuts it down.
	AndroidTestCore func(cfgPath string, out io.Writer) (stop func(), err error)
	// AndroidInstallApk hands a verified update APK to the system installer.
	AndroidInstallApk func(path string) error
	// AndroidRuleDir: rule sets copied out of the APK assets.
	AndroidRuleDir string
	// AndroidDNS: system DNS server used where desktop configs say "local" (Android has no
	// /etc/resolv.conf, so sing-box's local transport and Go's resolver cannot find one).
	AndroidDNS = "77.88.8.8"
)

func binPath(dir, n string) string { return filepath.Join(dir, "lib"+n+".so") } // jniLibs executables
func osName() string               { return "android" }
func ruleDir(string) string        { return AndroidRuleDir }

func applyUpdate(a *App, u *UpdateInfo) error {
	path, err := a.download(u) // sha256 + ed25519 verified
	if err != nil {
		return err
	}
	return installUpdate(a, path)
}

func installUpdate(a *App, path string) error {
	if AndroidInstallApk == nil {
		return errors.New("установщик недоступен")
	}
	return AndroidInstallApk(path)
}

// vpnProc: the libbox service owned by NoxVpnService. Wait returns when it stops.
type vpnProc struct {
	once sync.Once
	done chan struct{}
	err  error
}

var (
	curVpnMu sync.Mutex
	curVpn   *vpnProc
)

// VpnStopped is called by the mobile layer when the VpnService stops (user, revoke, error).
func VpnStopped(msg string) {
	curVpnMu.Lock()
	p := curVpn
	curVpn = nil
	curVpnMu.Unlock()
	if p != nil {
		p.once.Do(func() {
			if msg != "" {
				p.err = errors.New(msg)
			}
			close(p.done)
		})
	}
}

func (p *vpnProc) Wait() error { <-p.done; return p.err }
func (p *vpnProc) Stop() {
	if AndroidStopVpn != nil {
		AndroidStopVpn()
	}
	VpnStopped("")
}

func startCore(a *App, cfg string, tun bool, out io.WriteCloser) (coreProc, error) {
	if AndroidStartVpn == nil {
		return nil, errors.New("VPN-служба недоступна")
	}
	a.mu.Lock()
	st := a.p.Settings
	a.mu.Unlock()
	split, apps := effectiveSplit(st.SplitMode, st.SplitApps, st.RuApps, st.RuAppsOff)
	if err := PatchAndroidConfigSplit(cfg, true, split, apps); err != nil {
		return nil, err
	}
	p := &vpnProc{done: make(chan struct{})}
	curVpnMu.Lock()
	curVpn = p
	curVpnMu.Unlock()
	if err := AndroidStartVpn(cfg, tun); err != nil {
		VpnStopped(err.Error())
		return nil, err
	}
	return p, nil
}

type funcProc struct {
	stop func()
	done chan struct{}
	once sync.Once
}

func (p *funcProc) Wait() error { <-p.done; return nil }
func (p *funcProc) Stop()       { p.once.Do(func() { p.stop(); close(p.done) }) }

func startTestCore(a *App, cfg string, out io.Writer) (coreProc, error) {
	if AndroidTestCore == nil {
		return nil, errors.New("тестовое ядро недоступно")
	}
	if err := PatchAndroidConfig(cfg, false); err != nil {
		return nil, err
	}
	stop, err := AndroidTestCore(cfg, out)
	if err != nil {
		return nil, err
	}
	return &funcProc{stop: stop, done: make(chan struct{})}, nil
}

// PatchAndroidConfig rewrites desktop-only bits of a generated sing-box config:
// DNS servers of type "local" become plain UDP to the system resolver, and
// default_interface is dropped (the app is excluded from its own VPN, and libbox protects
// its sockets through VpnService.protect).
func PatchAndroidConfig(path string, vpn bool) error {
	return PatchAndroidConfigSplit(path, vpn, "", nil)
}

// PatchAndroidConfigSplit also applies per-app split tunnelling to the TUN inbound
// (libbox hands include/exclude_package to VpnService.Builder).
func PatchAndroidConfigSplit(path string, vpn bool, split string, apps []string) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var cfg map[string]any
	if err := json.Unmarshal(b, &cfg); err != nil {
		return err
	}
	if dns, ok := cfg["dns"].(map[string]any); ok {
		if servers, ok := dns["servers"].([]any); ok {
			for _, s := range servers {
				if m, ok := s.(map[string]any); ok && m["type"] == "local" {
					m["type"] = "udp"
					m["server"] = AndroidDNS
				}
			}
		}
	}
	if r, ok := cfg["route"].(map[string]any); ok {
		delete(r, "default_interface")
		if vpn {
			r["auto_detect_interface"] = true // libbox: platform interface monitor + protect()
		} else {
			delete(r, "auto_detect_interface") // plain in-process box: no netlink on Android 11+
		}
	}
	if ins, ok := cfg["inbounds"].([]any); ok {
		for _, in := range ins {
			if m, ok := in.(map[string]any); ok && m["type"] == "tun" {
				delete(m, "interface_name")
				m["stack"] = "gvisor" // "system" stack needs a writable TUN address on the host side
				// LAN bypasses the VPN entirely (pairing with a TV, printers, NAS); 172.19.0.0/16 stays
				// inside because it holds our own TUN address and DNS.
				m["route_exclude_address"] = LanExclude4
				if len(apps) > 0 && (split == "include" || split == "exclude") {
					m[split+"_package"] = apps
				}
			}
		}
	}
	out, _ := json.Marshal(cfg)
	return os.WriteFile(path, out, 0o600)
}
