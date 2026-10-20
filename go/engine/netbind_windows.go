//go:build windows

package engine

import (
	"encoding/binary"
	"net"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// physNIC is the real network adapter (Ethernet/Wi-Fi) that carries the default route
// outside of any VPN. Ping sockets are pinned to it with IP_UNICAST_IF so that a running
// TUN / SSTP tunnel is neither used nor disturbed while servers are checked.
type physNIC struct {
	Name   string // FriendlyName (= Go net.Interface.Name, = sing-box default_interface)
	V4, V6 uint32
}

const (
	ipUnicastIf   = 31 // IP_UNICAST_IF
	ipv6UnicastIf = 31 // IPV6_UNICAST_IF
	ifTypeVirtual = 53 // IF_TYPE_PROP_VIRTUAL (wintun, many VPN adapters)
	ifTypeLoop    = 24
)

var vpnWords = []string{"wintun", "wireguard", "openvpn", "ovpn", "tap-win", "tap-windows", "sing-tun", "sing-box",
	"sstp", "wan miniport", "zerotier", "tailscale", "hyper-v", "vethernet", "virtualbox", "vmware", "npcap", "loopback", "dco"}

// tetherWords: phone/USB/Bluetooth tethering adapters are real uplinks even when Windows
// reports them as virtual/WWAN.
var tetherWords = []string{"rndis", "remote ndis", "usb", "bluetooth", "apple mobile device", "mobile broadband", "wwan", "tether", "android"}

func isTether(name, desc string, typ uint32) bool {
	if typ == 243 || typ == 244 { // IF_TYPE_WWANPP / WWANPP2
		return true
	}
	all := strings.ToLower(name + " " + desc)
	for _, w := range tetherWords {
		if strings.Contains(all, w) {
			return true
		}
	}
	return false
}

func isVPNAdapter(name, desc string, typ uint32) bool {
	if isTether(name, desc, typ) {
		return false
	}
	switch typ {
	case windows.IF_TYPE_PPP, windows.IF_TYPE_TUNNEL, ifTypeVirtual, ifTypeLoop:
		return true
	}
	n := strings.ToLower(strings.TrimSpace(name))
	if n == "nox" || n == "vps" || strings.HasPrefix(n, "tun") || strings.HasPrefix(n, "nox ") {
		return true
	}
	all := n + " " + strings.ToLower(desc)
	for _, w := range vpnWords {
		if strings.Contains(all, w) {
			return true
		}
	}
	return false
}

func adapters() []*windows.IpAdapterAddresses {
	size := uint32(16 << 10)
	for i := 0; i < 4; i++ {
		buf := make([]byte, size)
		aa := (*windows.IpAdapterAddresses)(unsafe.Pointer(&buf[0]))
		err := windows.GetAdaptersAddresses(windows.AF_UNSPEC, windows.GAA_FLAG_INCLUDE_GATEWAYS|windows.GAA_FLAG_SKIP_ANYCAST|windows.GAA_FLAG_SKIP_MULTICAST|windows.GAA_FLAG_SKIP_DNS_SERVER, 0, aa, &size)
		if err == windows.ERROR_BUFFER_OVERFLOW {
			continue
		}
		if err != nil {
			return nil
		}
		var out []*windows.IpAdapterAddresses
		for p := aa; p != nil; p = p.Next {
			out = append(out, p)
		}
		return out
	}
	return nil
}

// bestIfNow asks Windows which interface routes to the Internet right now. Only meaningful
// while no tunnel is up; used to remember the physical NIC just before connecting.
func bestIfNow() uint32 {
	var idx uint32
	sa := &windows.SockaddrInet4{Addr: [4]byte{1, 1, 1, 1}}
	if windows.GetBestInterfaceEx(sa, &idx) != nil {
		return 0
	}
	return idx
}

// findPhysNIC picks the physical adapter: the remembered one (if still up with a gateway),
// otherwise the up adapter with a default gateway, not a VPN/virtual one, preferring
// Ethernet/Wi-Fi and the lowest IPv4 metric.
func findPhysNIC(hint uint32) (physNIC, bool) {
	var best *windows.IpAdapterAddresses
	score := func(p *windows.IpAdapterAddresses) uint32 {
		s := p.Ipv4Metric
		if p.IfType != windows.IF_TYPE_ETHERNET_CSMACD && p.IfType != windows.IF_TYPE_IEEE80211 &&
			!isTether(windows.UTF16PtrToString(p.FriendlyName), windows.UTF16PtrToString(p.Description), p.IfType) {
			s += 10000
		}
		return s
	}
	for _, p := range adapters() {
		if p.OperStatus != windows.IfOperStatusUp || p.FirstGatewayAddress == nil {
			continue
		}
		name, desc := windows.UTF16PtrToString(p.FriendlyName), windows.UTF16PtrToString(p.Description)
		if isVPNAdapter(name, desc, p.IfType) {
			continue
		}
		if hint != 0 && p.IfIndex == hint {
			best = p
			break
		}
		if best == nil || score(p) < score(best) {
			best = p
		}
	}
	if best == nil {
		return physNIC{}, false
	}
	return physNIC{Name: windows.UTF16PtrToString(best.FriendlyName), V4: best.IfIndex, V6: best.Ipv6IfIndex}, true
}

// bindControl pins a socket to the NIC (IPv4 index in network byte order, IPv6 in host order).
func bindControl(n physNIC) func(network, address string, c syscall.RawConn) error {
	return func(network, address string, c syscall.RawConn) error {
		var serr error
		err := c.Control(func(fd uintptr) {
			h := windows.Handle(fd)
			if strings.HasSuffix(network, "6") {
				if n.V6 != 0 {
					serr = windows.SetsockoptInt(h, windows.IPPROTO_IPV6, ipv6UnicastIf, int(n.V6))
				}
				return
			}
			var b [4]byte
			binary.BigEndian.PutUint32(b[:], n.V4)
			serr = windows.SetsockoptInt(h, windows.IPPROTO_IP, ipUnicastIf, int(int32(binary.LittleEndian.Uint32(b[:]))))
		})
		if err != nil {
			return err
		}
		return serr
	}
}

var _ = net.IPv4len
