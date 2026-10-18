package core

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestParseXhttp(t *testing.T) {
	l := "vless://11111111-2222-3333-4444-555555555555@canada2.iji.by:2087?encryption=none&type=xhttp&path=%2Fxh&host=canada2.iji.by&mode=auto&security=tls&sni=canada2.iji.by&fp=chrome&alpn=h2%2Chttp%2F1.1#%F0%9F%87%AC%F0%9F%87%A7%20%D0%9B%D0%9E%D0%9D%D0%94%D0%9E%D0%9D%202%202087"
	s, err := ParseLink(l)
	if err != nil {
		t.Fatal(err)
	}
	if s.Type != "VLESS XHTTP" || s.Host != "canada2.iji.by" || s.Port != 2087 || !IsXray(s.Outbound) {
		t.Fatalf("%+v", s)
	}
	b, err := XrayConfig([]XrayEntry{{Outbound: s.Outbound, Port: 30001, IP: "31.76.249.120"}})
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Inbounds  []map[string]any
		Outbounds []struct {
			Protocol       string
			Settings       map[string]any
			StreamSettings struct {
				Network       string
				Security      string
				TlsSettings   map[string]any
				XhttpSettings map[string]any
			}
		}
	}
	json.Unmarshal(b, &c)
	o := c.Outbounds[0]
	st := o.StreamSettings
	if o.Protocol != "vless" || st.Network != "xhttp" || st.Security != "tls" || st.XhttpSettings["path"] != "/xh" ||
		st.XhttpSettings["host"] != "canada2.iji.by" || st.TlsSettings["serverName"] != "canada2.iji.by" ||
		st.TlsSettings["fingerprint"] != "chrome" || !strings.Contains(string(b), `"alpn":["h2","http/1.1"]`) ||
		!strings.Contains(string(b), `"address":"31.76.249.120"`) || c.Inbounds[0]["port"] != float64(30001) {
		t.Fatal(string(b))
	}
	// extra JSON, Reality-less TLS, IP host
	l2 := "vless://u@107.161.174.157:443?type=xhttp&path=%2Fxhttp&host=turkish1.iji.by&mode=auto&extra=%7B%22mode%22%3A%22auto%22%7D&security=tls&sni=turkish1.iji.by&fp=firefox&alpn=h2#T"
	s2, err := ParseLink(l2)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(s2.Outbound), `"extra":{"mode":"auto"}`) || !strings.Contains(string(s2.Outbound), `"serverName":"turkish1.iji.by"`) {
		t.Fatal(string(s2.Outbound))
	}
	// trojan over xhttp
	s3, err := ParseLink("trojan://pw@h.example:443?type=xhttp&path=%2Fx&sni=h.example#Tr")
	if err != nil || s3.Type != "Trojan XHTTP" {
		t.Fatal(err, s3.Type)
	}
}
