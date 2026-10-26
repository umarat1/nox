package extra

import (
	"context"

	"nox/noxproto"
)

func init() {
	kinds["nox"] = func(cfg map[string]any) (proto, error) {
		d, err := noxproto.NewDialer(cfg)
		if err != nil {
			return proto{}, err
		}
		return proto{
			dialTCP: func(ctx context.Context, host string, port uint16) (rwc, error) {
				return d.Dial(ctx, "tcp", host, port)
			},
			dialUDP: func(ctx context.Context, host string, port uint16) (rwc, error) {
				return d.Dial(ctx, "udp", host, port)
			},
			stop: func() { d.Close() },
		}, nil
	}
}
