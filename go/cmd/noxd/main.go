// noxd — Nox core service. Windows: installed as the "Nox" service (LocalSystem, auto start),
// so the UI never needs UAC and the VPN stays up when the window is closed.
//
//	noxd                 (started by the Service Control Manager)
//	noxd run [-data D]   foreground (debug, Linux dev)
//	noxd install|uninstall|start|stop   (used by the installer)
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"nox/engine"
	"nox/ipc"
)

const svcName = "Nox"

func dataDir() string {
	if pd := os.Getenv("ProgramData"); pd != "" {
		return filepath.Join(pd, "Nox")
	}
	d, _ := os.UserConfigDir()
	return filepath.Join(d, "Nox")
}

// runCore starts engine + IPC and blocks until stop is closed.
func runCore(dir string, port int, service bool, stop <-chan struct{}) error {
	os.MkdirAll(dir, 0o755)
	if service {
		if err := ipc.RestrictDataDir(dir); err != nil {
			log.Printf("data dir ACL: %v", err)
		}
	}
	exe, _ := os.Executable()
	app := engine.NewApp(dir, filepath.Dir(exe))
	app.Service = service
	srv := ipc.New(app)
	info, err := srv.Listen(dir, port)
	if err != nil {
		return err
	}
	log.Printf("noxd %s: 127.0.0.1:%d, data %s", engine.Version, info.Port, dir)
	app.Start()
	go srv.Serve()
	<-stop
	srv.Close()
	app.Shutdown()
	os.Remove(filepath.Join(dir, "ipc.json"))
	return nil
}

func main() {
	// SCM starts us as `noxd.exe service`; detection is a fallback for older registrations.
	if (len(os.Args) > 1 && os.Args[1] == "service") || isService() {
		runService()
		return
	}
	cmd := "run"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}
	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	dir := fs.String("data", dataDir(), "data directory")
	port := fs.Int("port", 0, "IPC port (0 = random)")
	if len(os.Args) > 2 {
		fs.Parse(os.Args[2:])
	}
	var err error
	switch cmd {
	case "run":
		stop := make(chan struct{})
		go func() {
			c := make(chan os.Signal, 1)
			signal.Notify(c, os.Interrupt, syscall.SIGTERM)
			<-c
			close(stop)
		}()
		err = runCore(*dir, *port, false, stop)
	case "install":
		err = installService()
	case "uninstall":
		err = removeService()
	case "start":
		err = startService()
	case "stop":
		err = stopService()
	case "version":
		fmt.Println(engine.Version)
	default:
		err = fmt.Errorf("unknown command %q", cmd)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "noxd:", err)
		os.Exit(1)
	}
}
