package extra

import (
	"context"
	"net/netip"

	"github.com/metacubex/mihomo/adapter"
	C "github.com/metacubex/mihomo/constant"
)

func init() {
	kinds["mihomo"] = func(cfg map[string]any) (dialFn, func(), error) {
		p, err := adapter.ParseProxy(cfg)
		if err != nil {
			return nil, nil, err
		}
		d := func(ctx context.Context, host string, port uint16) (rwc, error) {
			if host == "" {
				return nil, errNoHost
			}
			m := &C.Metadata{NetWork: C.TCP, DstPort: port}
			if ip, err := netip.ParseAddr(host); err == nil {
				m.DstIP = ip
			} else {
				m.Host = host
			}
			return p.DialContext(ctx, m)
		}
		return d, func() { p.Close() }, nil
	}
}
