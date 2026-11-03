package engine

import "testing"

func TestShareInfoHostIfaces232(t *testing.T) {
	HostIfaces = func() []ShareIface {
		return []ShareIface{
			{"wlan0", []string{"192.168.1.37/24", "fe80::1/64"}},
			{"rmnet_data0", []string{"10.44.1.2/30"}},
			{"tun0", []string{"172.19.0.1/30"}},
			{"wlan1", []string{"192.168.127.211/24"}}, // Pixel / MIUI SoftAP
			{"ncm0", []string{"192.168.42.129/24"}},
		}
	}
	defer func() { HostIfaces = nil }()
	a := NewApp(t.TempDir(), t.TempDir())
	a.mu.Lock()
	a.p.Settings.AllowLAN = true
	a.mu.Unlock()
	r := a.ShareInfo()
	if r["hotspot"] != "192.168.127.211" || r["port"] != 10808 || r["on"] != true {
		t.Fatalf("%v", r)
	}
	ips := r["ips"].([]any)
	if len(ips) != 3 || ips[0].(map[string]any)["kind"] != "Точка доступа" || ips[1].(map[string]any)["kind"] != "USB-модем" || ips[2].(map[string]any)["kind"] != "Wi‑Fi" {
		t.Fatalf("%v", ips)
	}
	// only Wi‑Fi (phone is a client, no hotspot): nothing to type on a hotspot client
	HostIfaces = func() []ShareIface { return []ShareIface{{"wlan0", []string{"192.168.1.37/24"}}} }
	if r := a.ShareInfo(); r["hotspot"] != "" {
		t.Fatalf("%v", r)
	}
}
