package extra

import (
	"context"
	"errors"

	"github.com/daeuniverse/outbound/dialer"
	_ "github.com/daeuniverse/outbound/dialer/juicity"
	"github.com/daeuniverse/outbound/netproxy"
	sdirect "github.com/daeuniverse/outbound/protocol/direct"
	_ "github.com/daeuniverse/outbound/protocol/juicity"
	"sync"
)

var initDirect sync.Once

func init() {
	kinds["juicity"] = func(cfg map[string]any) (dialFn, func(), error) {
		link, _ := cfg["link"].(string)
		if link == "" {
			return nil, nil, errors.New("juicity: нет ссылки")
		}
		initDirect.Do(func() { sdirect.InitDirectDialers("1.1.1.1:53") })
		opt := &dialer.ExtraOption{}
		direct, _ := dialer.NewDirectDialer(opt, true)
		d, _, err := dialer.NewNetproxyDialerFromLink(direct, opt, link)
		if err != nil {
			return nil, nil, err
		}
		var nd netproxy.Dialer = d
		return func(ctx context.Context, host string, port uint16) (rwc, error) {
			return nd.DialContext(ctx, "tcp", hostPort(host, port))
		}, nil, nil
	}
}
