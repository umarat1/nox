package extra

import (
	"bufio"
	"context"
	"io"
	"net"
	"net/http"
	"testing"
)

// connectDialer tunnels through an HTTP CONNECT proxy (the МТС proxy), byte-exact both ways.
func TestConnectDialer233(t *testing.T) {
	echo, _ := net.Listen("tcp", "127.0.0.1:0")
	go func() {
		for {
			c, err := echo.Accept()
			if err != nil {
				return
			}
			go io.Copy(c, c)
		}
	}()
	px, _ := net.Listen("tcp", "127.0.0.1:0")
	var target string
	go func() {
		c, err := px.Accept()
		if err != nil {
			return
		}
		br := bufio.NewReader(c)
		req, _ := http.ReadRequest(br)
		target = req.Host
		u, _ := net.Dial("tcp", req.Host)
		c.Write([]byte("HTTP/1.1 200 Connection established\r\n\r\n"))
		go io.Copy(u, br)
		io.Copy(c, u)
	}()
	c, err := connectDialer{proxy: px.Addr().String()}.DialContext(context.Background(), "tcp", echo.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	c.Write([]byte("hello-mts"))
	b := make([]byte, 9)
	if _, err := io.ReadFull(c, b); err != nil || string(b) != "hello-mts" {
		t.Fatalf("echo %q %v", b, err)
	}
	if target != echo.Addr().String() {
		t.Fatalf("CONNECT target %q", target)
	}
	if _, err := (connectDialer{proxy: px.Addr().String()}).DialContext(context.Background(), "udp", "1.1.1.1:53"); err == nil {
		t.Fatal("udp must be refused")
	}
}
