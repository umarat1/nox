//go:build !android

package engine

import (
	"context"
	"fmt"

	"nox/core"
)

func (a *App) startSSTPAndroid(ctx context.Context, srv core.Server, s core.SSTP) error {
	return fmt.Errorf("SSTP: только Android")
}
func (a *App) stopSSTPAndroid() {}
