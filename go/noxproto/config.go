package noxproto

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"
)

// Carriers the client knows how to dial.
const (
	CarrierH2    = "h2"
	CarrierH3    = "h3"
	CarrierCDN   = "cdn"
	CarrierFront = "front"
)

// Config is everything a subscription has to say about one NOX server.
type Config struct {
	Addr        string // TCP dial address, host:port. HTTP/3 uses H3Addr when set, otherwise Addr.
	H3Addr      string
	SNI         string
	Authority   string // HTTP Host / :authority
	Path        string
	Pub         []byte
	Password    string
	Carriers    []string
	Front       string // dial this host instead of Addr when the carrier is front
	Profile     string
	Fingerprint string
	Insecure    bool
	Jitter      time.Duration
	JitterSet   bool
	MemFile     string
	Network     string
	Timeout     time.Duration
	Poll        time.Duration // CDN poll / server hold hint for the client
}

func (c Config) timeout() time.Duration {
	if c.Timeout <= 0 {
		return 12 * time.Second
	}
	return c.Timeout
}

func (c Config) poll() time.Duration {
	if c.Poll <= 0 {
		return 80 * time.Millisecond
	}
	return c.Poll
}

func (c Config) jitter() time.Duration {
	if c.JitterSet {
		return c.Jitter
	}
	return defaultJitter(c.Profile)
}

func (c Config) path() string {
	if c.Path == "" {
		return "/api/v1/events"
	}
	return c.Path
}

func (c Config) authority() string {
	if c.Authority != "" {
		return c.Authority
	}
	return c.SNI
}

func (c Config) validate() error {
	if _, _, err := net.SplitHostPort(c.Addr); err != nil {
		return fmt.Errorf("nox: адрес %q: %w", c.Addr, err)
	}
	if len(c.Pub) != 32 {
		return fmt.Errorf("nox: нужен открытый ключ сервера (32 байта)")
	}
	if c.SNI == "" {
		return fmt.Errorf("nox: не задан SNI")
	}
	if len(c.Carriers) == 0 {
		return fmt.Errorf("nox: не задан канал")
	}
	for _, k := range c.Carriers {
		switch k {
		case CarrierH2, CarrierH3, CarrierCDN, CarrierFront:
		default:
			return fmt.Errorf("nox: неизвестный канал %q", k)
		}
	}
	return nil
}

// ConfigFromMap reads the cfg object stored in a subscription outbound.
func ConfigFromMap(m map[string]any) (Config, error) {
	str := func(k string) string {
		s, _ := m[k].(string)
		return s
	}
	c := Config{
		Addr:        str("addr"),
		SNI:         str("sni"),
		Authority:   first(str("authority"), str("host")),
		Path:        str("path"),
		Password:    str("pass"),
		Front:       str("front"),
		Profile:     normalizeProfile(str("profile")),
		Fingerprint: str("fp"),
		MemFile:     str("memfile"),
		Network:     str("network"),
	}
	if c.Fingerprint == "" {
		c.Fingerprint = "chrome"
	}
	if p := str("pub"); p != "" {
		b, err := ParsePub(p)
		if err != nil {
			return Config{}, err
		}
		c.Pub = b
	}
	if c.Addr == "" {
		host := str("server")
		port := int(num(m["port"]))
		if port == 0 {
			port = 443
		}
		if host != "" {
			c.Addr = net.JoinHostPort(host, strconv.Itoa(port))
		}
	}
	if c.SNI == "" {
		host, _, _ := net.SplitHostPort(c.Addr)
		c.SNI = host
	}
	if c.Authority == "" {
		c.Authority = c.SNI
	}
	rawCar := str("carrier")
	if rawCar == "" {
		rawCar = CarrierH2
	}
	for _, part := range strings.Split(rawCar, ",") {
		part = strings.TrimSpace(strings.ToLower(part))
		if part != "" {
			c.Carriers = append(c.Carriers, part)
		}
	}
	if v, ok := m["insecure"]; ok {
		c.Insecure = truthy(v)
	}
	if v, ok := m["jitter"]; ok {
		c.JitterSet = true
		c.Jitter = time.Duration(num(v)) * time.Millisecond
	}
	if v, ok := m["poll"]; ok {
		c.Poll = time.Duration(num(v)) * time.Millisecond
	}
	if v, ok := m["timeout"]; ok {
		c.Timeout = time.Duration(num(v)) * time.Millisecond
	}
	if c.Network == "" {
		c.Network = NetworkLabel()
	}
	return c, c.validate()
}

func first(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

func num(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case int:
		return float64(x)
	case int64:
		return float64(x)
	case string:
		f, _ := strconv.ParseFloat(x, 64)
		return f
	default:
		return 0
	}
}

func truthy(v any) bool {
	switch x := v.(type) {
	case bool:
		return x
	case string:
		x = strings.ToLower(x)
		return x == "1" || x == "true" || x == "yes"
	case float64:
		return x != 0
	default:
		return false
	}
}

// NetworkLabel is a coarse fingerprint of the current machine's addresses.
// It changes when the phone moves between Wi-Fi and mobile data, which is
// what the path memory is keyed by.
func NetworkLabel() string {
	ifs, err := net.Interfaces()
	if err != nil {
		return "default"
	}
	h := sha256.New()
	n := 0
	for _, ifi := range ifs {
		if ifi.Flags&net.FlagUp == 0 || ifi.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := ifi.Addrs()
		if len(addrs) == 0 {
			continue
		}
		n++
		h.Write([]byte(ifi.Name))
		for _, a := range addrs {
			h.Write([]byte(a.String()))
		}
	}
	if n == 0 {
		return "default"
	}
	return hex.EncodeToString(h.Sum(nil)[:8])
}
