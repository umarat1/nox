package engine

import (
	"net"
	"sort"
	"strings"
)

// ShareInfo («Раздача VPN»): LAN addresses where the proxy (AllowLAN) is reachable —
// Wi‑Fi hotspot, USB tethering (rndis/ncm/usb) and the ordinary Wi‑Fi/Ethernet network.
func (a *App) ShareInfo() map[string]any {
	a.mu.Lock()
	st := a.p.Settings
	connected := a.status == "connected"
	a.mu.Unlock()
	port := st.ProxyPort
	if port == 0 {
		port = 2080
	}
	type ent struct{ Kind, Name, IP string }
	var list []ent
	for _, f := range shareIfaces() {
		n := strings.ToLower(f.Name)
		if strings.HasPrefix(n, "tun") || strings.HasPrefix(n, "nox") || strings.HasPrefix(n, "rmnet") || strings.HasPrefix(n, "ccmni") || strings.HasPrefix(n, "dummy") {
			continue
		}
		kind := "Сеть"
		switch {
		case strings.HasPrefix(n, "rndis") || strings.HasPrefix(n, "usb") || strings.HasPrefix(n, "ncm"):
			kind = "USB-модем"
		case strings.HasPrefix(n, "ap") || strings.HasPrefix(n, "swlan") || strings.HasPrefix(n, "softap") || strings.HasPrefix(n, "wlan1") || strings.HasPrefix(n, "wlan2") || strings.HasPrefix(n, "wifi_ap"):
			kind = "Точка доступа"
		case strings.HasPrefix(n, "wlan"):
			kind = "Wi‑Fi"
		}
		for _, ad := range f.Addrs {
			ip := net.ParseIP(strings.TrimSpace(strings.Split(ad, "/")[0])).To4()
			if ip == nil || !ip.IsPrivate() || (ip[0] == 172 && ip[1] == 19 && ip[2] == 0) {
				continue // 172.19.0.0/30 is our own TUN
			}
			list = append(list, ent{kind, f.Name, ip.String()})
		}
	}
	rank := func(k string) int {
		switch k {
		case "Точка доступа":
			return 0
		case "USB-модем":
			return 1
		case "Wi‑Fi":
			return 2
		}
		return 3
	}
	sort.SliceStable(list, func(i, j int) bool { return rank(list[i].Kind) < rank(list[j].Kind) })
	var out []any
	for _, e := range list {
		out = append(out, map[string]any{"kind": e.Kind, "name": e.Name, "ip": e.IP})
	}
	// "hotspot": the address to type on the hotspot client (car head unit, TV box, PC) —
	// hotspot first, then USB tethering; "" when neither is on.
	hot := ""
	if len(list) > 0 && rank(list[0].Kind) <= 1 {
		hot = list[0].IP
	}
	return map[string]any{"on": st.AllowLAN, "connected": connected, "port": port, "user": st.ShareUser, "pass": st.SharePass, "ips": out, "hotspot": hot}
}

// ShareIface: one network interface with its addresses ("ip/prefix").
type ShareIface struct {
	Name  string
	Addrs []string
}

// HostIfaces, when set (Android: java.net.NetworkInterface via the Kotlin host — Go's
// net.Interfaces needs netlink RTM_GETLINK, which apps may not use on Android 11+), lists
// the phone's interfaces including the hotspot (ap0 / swlan0 / wlan1) and USB tethering.
var HostIfaces func() []ShareIface

func shareIfaces() []ShareIface {
	if HostIfaces != nil {
		if l := HostIfaces(); len(l) > 0 {
			return l
		}
	}
	var out []ShareIface
	ifs, _ := net.Interfaces()
	for _, f := range ifs {
		if f.Flags&net.FlagUp == 0 || f.Flags&net.FlagLoopback != 0 {
			continue
		}
		e := ShareIface{Name: f.Name}
		as, _ := f.Addrs()
		for _, a := range as {
			e.Addrs = append(e.Addrs, a.String())
		}
		out = append(out, e)
	}
	return out
}
