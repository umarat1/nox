//go:build !windows

package engine

import "syscall"

type physNIC struct {
	Name   string
	V4, V6 uint32
}

func bestIfNow() uint32                       { return 0 }
func findPhysNIC(hint uint32) (physNIC, bool) { return physNIC{}, false }
func bindControl(n physNIC) func(network, address string, c syscall.RawConn) error {
	return nil
}
