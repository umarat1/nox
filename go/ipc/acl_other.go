//go:build !windows

package ipc

import "os"

func restrictInfoFile(p string) error { return os.Chmod(p, 0o600) }

// RestrictDataDir is a no-op off Windows (the dev/test daemon runs as the user).
func RestrictDataDir(string) error { return nil }
