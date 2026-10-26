//go:build android

package engine

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"nox/core"
	"nox/sstp"

	"golang.org/x/sys/unix"
)

// Filled by noxcore: open a VpnService TUN without starting libbox (SSTP owns the fd).
var (
	AndroidStartTunService func() error
	AndroidOpenTun         func(optionsJSON string) (fd int32, err error)
	AndroidStopTunService  func()
)

func (a *App) startSSTPAndroid(ctx context.Context, srv core.Server, s core.SSTP) error {
	if AndroidStartTunService == nil || AndroidOpenTun == nil {
		return fmt.Errorf("SSTP: Android TUN недоступен")
	}
	if err := AndroidStartTunService(); err != nil {
		return err
	}
	ip := s.Server
	if v := (pingNet{}).resolveDirect(s.Server); v != "" {
		ip = v
	}
	port := s.Port
	if port == 0 {
		port = 443
	}
	sni := s.SNI
	if sni == "" {
		sni = s.Server
	}
	sess, err := sstp.Dial(ctx, sstp.Config{
		Server: s.Server, Addr: ip, Port: port, User: s.User, Password: s.Password, SNI: sni, Insecure: s.Insecure,
		Logf: func(f string, v ...any) { a.log(fmt.Sprintf(f, v...)) },
	})
	if err != nil {
		if AndroidStopTunService != nil {
			AndroidStopTunService()
		}
		return err
	}
	local := sess.LocalIP.String()
	dns := []string{}
	for _, d := range sess.DNS {
		dns = append(dns, d.String())
	}
	if len(dns) == 0 {
		dns = append(dns, s.DNS...)
	}
	if len(dns) == 0 {
		dns = []string{"1.1.1.1", "8.8.8.8"}
	}
	a.mu.Lock()
	st := a.p.Settings
	a.mu.Unlock()
	split, apps := effectiveSplit(st.SplitMode, st.SplitApps, st.RuApps, st.RuAppsOff)
	opt := map[string]any{
		"mtu":       sess.MTU,
		"addr4":     []string{local + "/32"},
		"autoRoute": true,
		"routes4":   []string{"0.0.0.0/0"},
		"dns":       dns,
	}
	if len(apps) > 0 && (split == "include" || split == "exclude") {
		opt[split] = apps
	}
	jb, _ := json.Marshal(opt)
	fd32, err := AndroidOpenTun(string(jb))
	if err != nil {
		sess.Close()
		if AndroidStopTunService != nil {
			AndroidStopTunService()
		}
		return fmt.Errorf("SSTP: TUN: %w", err)
	}
	br := &sstpBridge{sess: sess, fd: int(fd32), stop: make(chan struct{})}
	a.mu.Lock()
	a.sstpBr = br
	a.sstpUp = true
	a.mu.Unlock()
	go a.sstpPump(br)
	go a.sstpTraffic(ctx, br)
	a.markConnected(srv.Name)
	a.log(fmt.Sprintf("SSTP: %s → %s DNS %v", local, sess.PeerIP, dns))
	return nil
}

func (a *App) sstpPump(br *sstpBridge) {
	go func() {
		buf := make([]byte, 32768)
		for {
			n, err := unix.Read(br.fd, buf)
			if err != nil || n <= 0 {
				return
			}
			if err := br.sess.WritePacket(append([]byte{}, buf[:n]...)); err != nil {
				return
			}
		}
	}()
	for {
		pkt, err := br.sess.ReadPacket()
		if err != nil {
			select {
			case <-br.stop:
				return
			default:
			}
			a.mu.Lock()
			live := a.sstpBr == br && (a.status == "connected" || a.status == "connecting")
			if live {
				a.errMsg = "SSTP: соединение разорвано"
			}
			a.mu.Unlock()
			if live {
				a.stopAll()
			}
			return
		}
		if _, err := unix.Write(br.fd, pkt); err != nil {
			return
		}
	}
}

func (a *App) sstpTraffic(ctx context.Context, br *sstpBridge) {
	var lastRx, lastTx uint64
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-br.stop:
			return
		case <-t.C:
			rx, tx := br.sess.Rx.Load(), br.sess.Tx.Load()
			up, down := int64(tx-lastTx), int64(rx-lastRx)
			lastTx, lastRx = tx, rx
			a.mu.Lock()
			a.up, a.down = up, down
			a.upTotal += up
			a.downTotal += down
			a.hist = append(a.hist, [2]int64{up, down})
			if len(a.hist) > 120 {
				a.hist = a.hist[len(a.hist)-120:]
			}
			a.histSeq++
			a.mu.Unlock()
		}
	}
}

func (a *App) stopSSTPAndroid() {
	a.mu.Lock()
	br := a.sstpBr
	a.sstpBr = nil
	a.sstpUp = false
	a.mu.Unlock()
	if br == nil {
		return
	}
	close(br.stop)
	br.sess.Close()
	unix.Close(br.fd)
	if AndroidStopTunService != nil {
		AndroidStopTunService()
	}
}
