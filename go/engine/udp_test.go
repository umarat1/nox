package engine

import (
	"testing"

	"nox/core"
)

func TestIsUDPServer(t *testing.T) {
	// 1. VLESS XHTTP with alpn=h3 ("UDP 1")
	s1, err := core.ParseLink("vless://453c6574-86ad-4792-bdbc-121f326abc43@moscow.iji.by:8443?encryption=none&security=tls&sni=moscow.iji.by&alpn=h3&fp=chrome&type=xhttp&host=moscow.iji.by&path=%2F7f5cb69e189578ab&mode=auto#%F0%9F%87%B7%F0%9F%87%BA%20%D0%9C%D0%9E%D0%A1%D0%9A%D0%92%D0%90%20UDP%201")
	if err != nil {
		t.Fatalf("ParseLink UDP 1 failed: %v", err)
	}
	if !isUDPServer(s1) {
		t.Fatalf("expected isUDPServer(s1) == true for VLESS XHTTP alpn=h3, got false (type=%s, outbound=%s)", s1.Type, string(s1.Outbound))
	}

	// 2. VLESS TCP Reality (not UDP)
	s2, err := core.ParseLink("vless://453c6574-86ad-4792-bdbc-121f326abc43@84.21.191.182:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=ads.x5.ru&fp=chrome&pbk=testpbk&sid=1234&type=tcp#TCP")
	if err != nil {
		t.Fatalf("ParseLink TCP Reality failed: %v", err)
	}
	if isUDPServer(s2) {
		t.Fatalf("expected isUDPServer(s2) == false for VLESS TCP Reality, got true")
	}
}
