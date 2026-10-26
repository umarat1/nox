//go:build !android

package engine

import (
	"context"
	"os/exec"
)

func command(bin string, args ...string) *exec.Cmd {
	return exec.Command(bin, args...)
}

func commandContext(ctx context.Context, bin string, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, bin, args...)
}
