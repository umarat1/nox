package extra

import (
	"context"
	"fmt"
	"net"
	"net/netip"

	"github.com/metacubex/mihomo/adapter"
	C "github.com/metacubex/mihomo/constant"
)

type pktRWC struct {
	pc  net.PacketConn
	dst net.Addr
}

func (p *pktRWC) Read(b []byte) (int, error) {
	n, _, err := p.pc.ReadFrom(b)
	return n, err
}

func (p *pktRWC) Write(b []byte) (int, error) {
	return p.pc.WriteTo(b, p.dst)
}

func (p *pktRWC) Close() error {
	return p.pc.Close()
}

func init() {
	kinds["mihomo"] = func(cfg map[string]any) (proto, error) {
		p, err := adapter.ParseProxy(cfg)
		if err != nil {
			return proto{}, err
		}
		dialTCP := func(ctx context.Context, host string, port uint16) (rwc, error) {
			m := &C.Metadata{NetWork: C.TCP, DstPort: port}
			if ip, err := netip.ParseAddr(host); err == nil {
				m.DstIP = ip
			} else {
				m.Host = host
			}
			return p.DialContext(ctx, m)
		}
		dialUDP := func(ctx context.Context, host string, port uint16) (rwc, error) {
			ip, err := netip.ParseAddr(host)
			if err != nil {
				ips, rerr := net.DefaultResolver.LookupNetIP(ctx, "ip4", host)
				if rerr != nil || len(ips) == 0 {
					ips, rerr = net.DefaultResolver.LookupNetIP(ctx, "ip", host)
				}
				if rerr != nil || len(ips) == 0 {
					return nil, fmt.Errorf("resolve %s: %v", host, rerr)
				}
				ip = ips[0]
			}
			m := &C.Metadata{NetWork: C.UDP, DstPort: port, DstIP: ip}
			if net.ParseIP(host) == nil {
				m.Host = host
			}
			pc, err := p.ListenPacketContext(ctx, m)
			if err != nil {
				return nil, err
			}
			dst := net.UDPAddrFromAddrPort(netip.AddrPortFrom(ip, port))
			return &pktRWC{pc: pc, dst: dst}, nil
		}
		return proto{
			dialTCP: dialTCP,
			dialUDP: dialUDP,
			stop:    func() { p.Close() },
		}, nil
	}
}
