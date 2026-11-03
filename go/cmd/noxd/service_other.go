//go:build !windows

package main

import "errors"

func isService() bool { return false }
func runService()     {}

var errNA = errors.New("only on Windows (use: noxd run)")

func installService() error { return errNA }
func removeService() error  { return errNA }
func startService() error   { return errNA }
func stopService() error    { return errNA }
