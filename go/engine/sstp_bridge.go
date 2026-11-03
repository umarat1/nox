package engine

import "nox/sstp"

// sstpBridge is the Android userspace SSTP↔TUN pump (nil on other OSes).
type sstpBridge struct {
	sess *sstp.Session
	fd   int
	stop chan struct{}
}
