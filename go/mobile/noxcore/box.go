package noxcore

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"sync"

	"github.com/sagernet/sing-box/experimental/libbox"
)

func setupLibbox(base string) error {
	os.MkdirAll(base, 0o755)
	return libbox.Setup(&libbox.SetupOptions{
		BasePath:        base,
		WorkingPath:     base,
		TempPath:        base,
		FixAndroidStack: true, // golang/go#68760: hop Java->Go callbacks onto a goroutine
		LogMaxLines:     300,
	})
}

var (
	boxMu  sync.Mutex
	mainCS *libbox.CommandServer
)

// startVpn: foreground VpnService first (OpenTun needs it), then libbox with the config.
func startVpn(cfgPath string, tun bool) error {
	b, err := os.ReadFile(cfgPath)
	if err != nil {
		return err
	}
	if err := host.StartService(tun); err != nil {
		return err
	}
	cs, err := libbox.NewCommandServer(cmdHandler{main: true}, &platform{})
	if err != nil {
		host.StopService()
		return err
	}
	if err := cs.StartOrReloadService(string(b), &libbox.OverrideOptions{}); err != nil {
		cs.Close()
		host.StopService()
		return err
	}
	boxMu.Lock()
	mainCS = cs
	boxMu.Unlock()
	return nil
}

func closeMain() {
	boxMu.Lock()
	cs := mainCS
	mainCS = nil
	boxMu.Unlock()
	if cs != nil {
		cs.CloseService()
		cs.Close()
	}
}

func stopVpn() {
	closeMain()
	host.StopService()
}

// testCore: a second, TUN-less sing-box in process for URL-test pings. The app is excluded
// from its own VPN, so its sockets take the physical network.
func testCore(cfgPath string, out io.Writer) (func(), error) {
	b, err := os.ReadFile(cfgPath)
	if err != nil {
		return nil, err
	}
	cs, err := libbox.NewCommandServer(cmdHandler{}, &platform{})
	if err != nil {
		return nil, err
	}
	if err := cs.StartOrReloadService(string(b), &libbox.OverrideOptions{}); err != nil {
		cs.Close()
		return nil, err
	}
	return func() { cs.CloseService(); cs.Close() }, nil
}

type cmdHandler struct{ main bool }

func (h cmdHandler) ServiceStop() error {
	if h.main {
		go VpnStopped("")
	}
	return nil
}
func (cmdHandler) ServiceReload() error { return nil }
func (cmdHandler) GetSystemProxyStatus() (*libbox.SystemProxyStatus, error) {
	return &libbox.SystemProxyStatus{}, nil
}
func (cmdHandler) SetSystemProxyEnabled(bool) error { return nil }
func (cmdHandler) TriggerNativeCrash() error        { return nil }
func (cmdHandler) WriteDebugMessage(string)         {}
func (cmdHandler) ConnectSSHAgent() (int32, error)  { return 0, errNA }

var errNA = errors.New("not supported")

// ---- libbox.PlatformInterface, mostly delegated to Host ----

type platform struct{}

func (*platform) LocalDNSTransport() libbox.LocalDNSTransport { return nil }
func (*platform) UsePlatformAutoDetectInterfaceControl() bool { return true }
func (*platform) AutoDetectInterfaceControl(fd int32) error {
	host.Protect(fd) // false when no VpnService is up: the socket is not routed into a TUN then
	return nil
}

type tunJSON struct {
	MTU       int32    `json:"mtu"`
	Addr4     []string `json:"addr4"`
	Addr6     []string `json:"addr6"`
	AutoRoute bool     `json:"autoRoute"`
	Routes4   []string `json:"routes4"`
	Routes6   []string `json:"routes6"`
	DNS       []string `json:"dns"`
	Include   []string `json:"include"`
	Exclude   []string `json:"exclude"`
	HTTPProxy bool     `json:"httpProxy"`
	ProxyHost string   `json:"proxyHost"`
	ProxyPort int32    `json:"proxyPort"`
	Bypass    []string `json:"bypass"`
}

func prefixes(it libbox.RoutePrefixIterator) []string {
	var out []string
	for it != nil && it.HasNext() {
		out = append(out, it.Next().String())
	}
	return out
}

func strs(it libbox.StringIterator) []string {
	var out []string
	for it != nil && it.HasNext() {
		out = append(out, it.Next())
	}
	return out
}

func (*platform) OpenTun(o libbox.TunOptions) (int32, error) {
	t := tunJSON{MTU: o.GetMTU(), Addr4: prefixes(o.GetInet4Address()), Addr6: prefixes(o.GetInet6Address()),
		AutoRoute: o.GetAutoRoute(), Include: strs(o.GetIncludePackage()), Exclude: strs(o.GetExcludePackage())}
	if t.AutoRoute {
		t.Routes4 = prefixes(o.GetInet4RouteRange())
		t.Routes6 = prefixes(o.GetInet6RouteRange())
	} else {
		t.Routes4 = prefixes(o.GetInet4RouteAddress())
		t.Routes6 = prefixes(o.GetInet6RouteAddress())
	}
	if d, err := o.GetDNSServerAddress(); err == nil {
		t.DNS = strs(d)
	}
	if o.IsHTTPProxyEnabled() {
		t.HTTPProxy, t.ProxyHost, t.ProxyPort = true, o.GetHTTPProxyServer(), o.GetHTTPProxyServerPort()
		t.Bypass = strs(o.GetHTTPProxyBypassDomain())
	}
	b, _ := json.Marshal(t)
	return host.OpenTun(string(b))
}

func (*platform) UseProcFS() bool { return false }
func (*platform) FindConnectionOwner(int32, string, int32, string, int32) (*libbox.ConnectionOwner, error) {
	return nil, errNA
}

// Default network: Kotlin's ConnectivityManager callback -> DefaultInterfaceChanged ->
// every live listener (main tunnel and ping instance each register one).
var (
	monMu     sync.Mutex
	listeners = map[libbox.InterfaceUpdateListener]bool{}
	lastIf    *ifState
)

type ifState struct {
	name      string
	index     int32
	expensive bool
}

func (*platform) StartDefaultInterfaceMonitor(l libbox.InterfaceUpdateListener) error {
	monMu.Lock()
	listeners[l] = true
	first := len(listeners) == 1
	cur := lastIf
	monMu.Unlock()
	if first {
		host.StartNetMonitor()
	}
	if cur != nil {
		l.UpdateDefaultInterface(cur.name, cur.index, cur.expensive, false)
	}
	return nil
}

func (*platform) CloseDefaultInterfaceMonitor(l libbox.InterfaceUpdateListener) error {
	monMu.Lock()
	delete(listeners, l)
	monMu.Unlock()
	return nil
}

// DefaultInterfaceChanged is called from Kotlin; index -1 = no network.
func DefaultInterfaceChanged(name string, index int32, expensive bool) {
	monMu.Lock()
	lastIf = &ifState{name, index, expensive}
	ls := make([]libbox.InterfaceUpdateListener, 0, len(listeners))
	for l := range listeners {
		ls = append(ls, l)
	}
	monMu.Unlock()
	for _, l := range ls {
		l.UpdateDefaultInterface(name, index, expensive, false)
	}
}

type ifJSON struct {
	Name    string   `json:"name"`
	Index   int32    `json:"index"`
	MTU     int32    `json:"mtu"`
	Flags   int32    `json:"flags"`
	Type    int32    `json:"type"`
	Addrs   []string `json:"addrs"`
	DNS     []string `json:"dns"`
	Metered bool     `json:"metered"`
}

type strIter struct{ v []string }

func (i *strIter) Len() int32    { return int32(len(i.v)) }
func (i *strIter) HasNext() bool { return len(i.v) > 0 }
func (i *strIter) Next() string {
	if len(i.v) == 0 {
		return ""
	}
	s := i.v[0]
	i.v = i.v[1:]
	return s
}

type ifIter struct{ v []*libbox.NetworkInterface }

func (i *ifIter) HasNext() bool { return len(i.v) > 0 }
func (i *ifIter) Next() *libbox.NetworkInterface {
	if len(i.v) == 0 {
		return nil
	}
	n := i.v[0]
	i.v = i.v[1:]
	return n
}

func (*platform) GetInterfaces() (libbox.NetworkInterfaceIterator, error) {
	s, err := host.GetInterfaces()
	if err != nil {
		return nil, err
	}
	var l []ifJSON
	if err := json.Unmarshal([]byte(s), &l); err != nil {
		return nil, err
	}
	out := &ifIter{}
	for _, x := range l {
		out.v = append(out.v, &libbox.NetworkInterface{Index: x.Index, MTU: x.MTU, Name: x.Name,
			Addresses: &strIter{x.Addrs}, Flags: x.Flags, Type: x.Type, DNSServer: &strIter{x.DNS},
			Gateway: &strIter{}, Metered: x.Metered})
	}
	return out, nil
}

func (*platform) UnderNetworkExtension() bool                              { return false }
func (*platform) IncludeAllNetworks() bool                                 { return false }
func (*platform) ReadWIFIState() *libbox.WIFIState                         { return nil }
func (*platform) ClearDNSCache()                                           {}
func (*platform) SendNotification(*libbox.Notification) error              { return nil }
func (*platform) CancelNotification(string, int32) error                   { return nil }
func (*platform) StartNeighborMonitor(libbox.NeighborUpdateListener) error { return nil }
func (*platform) CloseNeighborMonitor(libbox.NeighborUpdateListener) error { return nil }
func (*platform) RegisterMyInterface(string)                               {}
func (*platform) UsePlatformShell() bool                                   { return false }
func (*platform) CheckPlatformShell() error                                { return errNA }
func (*platform) OpenShellSession(*libbox.PlatformUser, string, libbox.StringIterator, string, int32, int32) (libbox.ShellSession, error) {
	return nil, errNA
}
func (*platform) LookupUser(string) (*libbox.PlatformUser, error) { return nil, errNA }
func (*platform) LookupSFTPServer() (string, error)               { return "", errNA }
func (*platform) ReadSystemSSHHostKey() (string, error)           { return "", errNA }
func (*platform) TailscaleHostname() string                       { return "" }
func (*platform) UsePlatformBridge() bool                         { return false }
func (*platform) CreateBridge(*libbox.BridgeOptions) (libbox.BridgeSession, error) {
	return nil, errNA
}

var _ libbox.PlatformInterface = (*platform)(nil)
