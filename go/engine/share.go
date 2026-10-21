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
	ifs, _ := net.Interfaces()
	for _, f := range ifs {
		if f.Flags&net.FlagUp == 0 || f.Flags&net.FlagLoopback != 0 {
			continue
		}
		n := strings.ToLower(f.Name)
		if strings.HasPrefix(n, "tun") || strings.HasPrefix(n, "nox") || strings.HasPrefix(n, "rmnet") || strings.HasPrefix(n, "ccmni") || strings.HasPrefix(n, "dummy") {
			continue
		}
		kind := "Сеть"
		switch {
		case strings.HasPrefix(n, "rndis") || strings.HasPrefix(n, "usb") || strings.HasPrefix(n, "ncm"):
			kind = "USB-модем"
		case strings.HasPrefix(n, "ap") || strings.HasPrefix(n, "swlan") || strings.HasPrefix(n, "softap") || strings.HasPrefix(n, "wlan1"):
			kind = "Точка доступа"
		case strings.HasPrefix(n, "wlan"):
			kind = "Wi‑Fi"
		}
		addrs, _ := f.Addrs()
		for _, ad := range addrs {
			ipn, ok := ad.(*net.IPNet)
			if !ok || ipn.IP.To4() == nil || !ipn.IP.IsPrivate() || ipn.IP.String() == "172.19.0.1" {
				continue
			}
			list = append(list, ent{kind, f.Name, ipn.IP.String()})
		}
	}
	sort.SliceStable(list, func(i, j int) bool { return list[i].Kind != "Сеть" && list[j].Kind == "Сеть" })
	var out []any
	for _, e := range list {
		out = append(out, map[string]any{"kind": e.Kind, "name": e.Name, "ip": e.IP})
	}
	return map[string]any{"on": st.AllowLAN, "connected": connected, "port": port, "user": st.ShareUser, "pass": st.SharePass, "ips": out}
}
