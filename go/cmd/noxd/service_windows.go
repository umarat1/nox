//go:build windows

package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/eventlog"
	"golang.org/x/sys/windows/svc/mgr"
)

func isService() bool { ok, _ := svc.IsWindowsService(); return ok }

type handler struct{}

func (handler) Execute(_ []string, r <-chan svc.ChangeRequest, st chan<- svc.Status) (bool, uint32) {
	st <- svc.Status{State: svc.StartPending}
	stop := make(chan struct{})
	done := make(chan error, 1)
	go func() { done <- runCore(dataDir(), 0, true, stop) }()
	st <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	relaunchUIIfMarked(dataDir())
	for {
		select {
		case err := <-done:
			if err != nil {
				log.Print(err)
				return true, 1
			}
			return false, 0
		case c := <-r:
			switch c.Cmd {
			case svc.Interrogate:
				st <- c.CurrentStatus
			case svc.Stop, svc.Shutdown:
				st <- svc.Status{State: svc.StopPending}
				close(stop)
				select {
				case <-done:
				case <-time.After(15 * time.Second):
				}
				return false, 0
			}
		}
	}
}

func runService() {
	if el, err := eventlog.Open(svcName); err == nil {
		log.SetOutput(elWriter{el})
	}
	os.MkdirAll(dataDir(), 0o755)
	if f, err := os.OpenFile(filepath.Join(dataDir(), "noxd.log"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644); err == nil {
		log.SetOutput(f)
	}
	svc.Run(svcName, handler{})
}

type elWriter struct{ *eventlog.Log }

func (w elWriter) Write(b []byte) (int, error) { w.Info(1, string(b)); return len(b), nil }

func installService() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()
	if s, err := m.OpenService(svcName); err == nil { // reinstall/upgrade: update binary path
		defer s.Close()
		bin, _ := windows.UTF16PtrFromString(`"` + exe + `" service`)
		return windows.ChangeServiceConfig(s.Handle, windows.SERVICE_NO_CHANGE, windows.SERVICE_AUTO_START,
			windows.SERVICE_NO_CHANGE, bin, nil, nil, nil, nil, nil, nil)
	}
	s, err := m.CreateService(svcName, exe, mgr.Config{ // binary path: "exe" service
		DisplayName:  "Nox VPN",
		Description:  "Ядро Nox: подключение VPN (sing-box, qWDTT, SSTP) и пинг серверов",
		StartType:    mgr.StartAutomatic,
		ErrorControl: mgr.ErrorNormal,
	}, "service")
	if err != nil {
		return err
	}
	defer s.Close()
	s.SetRecoveryActions([]mgr.RecoveryAction{
		{Type: mgr.ServiceRestart, Delay: 2 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 5 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 30 * time.Second},
	}, 86400)
	eventlog.InstallAsEventCreate(svcName, eventlog.Error|eventlog.Warning|eventlog.Info)
	return nil
}

func removeService() error {
	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()
	s, err := m.OpenService(svcName)
	if err != nil {
		return nil
	}
	defer s.Close()
	s.Control(svc.Stop)
	waitState(s, svc.Stopped, 15*time.Second)
	eventlog.Remove(svcName)
	return s.Delete()
}

func startService() error {
	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()
	s, err := m.OpenService(svcName)
	if err != nil {
		return err
	}
	defer s.Close()
	if err := s.Start(); err != nil {
		return err
	}
	return waitState(s, svc.Running, 15*time.Second)
}

func stopService() error {
	m, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer m.Disconnect()
	s, err := m.OpenService(svcName)
	if err != nil {
		return nil
	}
	defer s.Close()
	s.Control(svc.Stop)
	return waitState(s, svc.Stopped, 15*time.Second)
}

func waitState(s *mgr.Service, want svc.State, d time.Duration) error {
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		q, err := s.Query()
		if err != nil {
			return err
		}
		if q.State == want {
			return nil
		}
		time.Sleep(300 * time.Millisecond)
	}
	return fmt.Errorf("service did not reach state %d", want)
}
