//go:build android

package engine

import (
	"context"
	"os/exec"
	"runtime"
)

// command starts a bundled PIE (qwdtt, xray, naive). Android 10+ (targetSdk 29+)
// forbids execve of files in the app home directory, and with extractNativeLibs=false
// the installer does not copy lib/*.so onto an executable filesystem. The dynamic
// linker is a system binary the app is allowed to execute; it loads the PIE and
// jumps to its entry point. argv[0] seen by the program is the binary path.
func command(bin string, args ...string) *exec.Cmd {
	return androidCommand(context.Background(), bin, args...)
}

func commandContext(ctx context.Context, bin string, args ...string) *exec.Cmd {
	if ctx == nil {
		ctx = context.Background()
	}
	return androidCommand(ctx, bin, args...)
}

func androidCommand(ctx context.Context, bin string, args ...string) *exec.Cmd {
	linker := "/system/bin/linker64"
	if runtime.GOARCH == "arm" || runtime.GOARCH == "386" {
		linker = "/system/bin/linker"
	}
	all := make([]string, 0, 1+len(args))
	all = append(all, bin)
	all = append(all, args...)
	return exec.CommandContext(ctx, linker, all...)
}
