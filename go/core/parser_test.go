package core

import (
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const links = `vless://11111111-2222-3333-4444-555555555555@nl.example.com:443?type=tcp&security=reality&pbk=PUBKEY&sid=ab12&sni=www.google.com&fp=chrome&flow=xtls-rprx-vision#%F0%9F%87%B3%F0%9F%87%B1%20NL
vless://11111111-2222-3333-4444-555555555555@ws.example.com:443?type=ws&security=tls&path=%2Fws%3Fed%3D2048&host=cdn.example.com#WS
trojan://pass@tr.example.com:443?sni=tr.example.com#Trojan
ss://` + "Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpzZWNyZXQ" + `@1.2.3.4:8388#SS
hy2://authpw@hy.example.com:8443?sni=hy.example.com&insecure=1&obfs=salamander&obfs-password=x#HY2
tuic://uuid:pw@tu.example.com:443?congestion_control=bbr&alpn=h3#TUIC
qwdtt://config?name=QW&peer=5.6.7.8&hashes=https://vk.com/call/join/abc,def&pass=secret&workers=20&port=9001
xhttp-bad://nothing`

func TestPlainAndBase64(t *testing.T) {
	defer func(o bool) { XrayReality = o }(XrayReality)
	XrayReality = false
	vm, _ := json.Marshal(map[string]any{"v": "2", "ps": "VM", "add": "vm.example.com", "port": "443", "id": "uuid", "aid": "0", "net": "grpc", "path": "svc", "tls": "tls"})
	all := links + "\nvmess://" + base64.StdEncoding.EncodeToString(vm)
	for _, body := range []string{all, base64.StdEncoding.EncodeToString([]byte(all))} {
		r := ParseContent(body)
		if len(r.Servers) != 8 {
			t.Fatalf("want 8 got %d errs=%v", len(r.Servers), r.Errors)
		}
		names := []string{}
		for _, s := range r.Servers {
			names = append(names, s.Name+"|"+s.Type)
		}
		t.Log(strings.Join(names, ", "))
		var ob map[string]any
		json.Unmarshal(r.Servers[0].Outbound, &ob)
		if ob["flow"] != "xtls-rprx-vision" || ob["tls"].(map[string]any)["reality"].(map[string]any)["public_key"] != "PUBKEY" {
			t.Fatal("reality", string(r.Servers[0].Outbound))
		}
		json.Unmarshal(r.Servers[1].Outbound, &ob)
		if ob["transport"].(map[string]any)["max_early_data"].(float64) != 2048 {
			t.Fatal("ws ed", string(r.Servers[1].Outbound))
		}
		q, err := QwdttFromOutbound(r.Servers[6].Outbound)
		if err != nil || q.Peer != "5.6.7.8:56000" || len(q.Hashes) != 2 || q.Hashes[0] != "abc" || q.LocalPort != 9001 || q.EffectiveWorkers() != 18 {
			t.Fatalf("qwdtt %+v %v", q, err)
		}
		if r.Servers[3].Host != "1.2.3.4" || r.Servers[7].Type != "VMess" {
			t.Fatal("ss/vmess")
		}
	}
}

func TestSingBoxJSON(t *testing.T) {
	j := `{"outbounds":[{"type":"selector","tag":"sel"},{"type":"vless","tag":"DE","server":"de.x","server_port":443,"uuid":"u"},{"type":"direct","tag":"direct"}]}`
	r := ParseContent(j)
	if len(r.Servers) != 1 || r.Servers[0].Name != "DE" || r.Servers[0].Port != 443 {
		t.Fatalf("%+v", r)
	}
}

func TestLinkJSONAndKeepalive(t *testing.T) {
	body := `{"links":["vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?security=tls#DE"],"announce":"https://example.com"}`
	r := ParseContent(body)
	if len(r.Servers) != 1 || r.Servers[0].Host != "1.2.3.4" || r.Servers[0].Name != "DE" {
		t.Fatalf("%+v", r)
	}
	raw := base64.StdEncoding.EncodeToString([]byte(`{"outbounds":[{"type":"trojan","tag":"T","server":"t.example","server_port":443,"password":"p"}]}`))
	r = ParseContent(raw)
	if len(r.Servers) != 1 || r.Servers[0].Name != "T" {
		t.Fatalf("b64 json %+v", r.Servers)
	}
	ep, err := WgEndpoint("[Interface]\nPrivateKey = PK\nAddress = 10.0.0.2\n[Peer]\nPublicKey = PUB\nAllowedIPs = 0.0.0.0/0\nEndpoint = 127.0.0.1:9000\n")
	if err != nil {
		t.Fatal(err)
	}
	peers := ep["peers"].([]any)
	if peers[0].(map[string]any)["persistent_keepalive_interval"] != 25 {
		t.Fatal(ep)
	}
}

func TestWgAndConfig(t *testing.T) {
	ep, err := WgEndpoint("[Interface]\nPrivateKey = PK\nAddress = 10.68.0.5\nMTU = 1280\n[Peer]\nPublicKey = PUB\nAllowedIPs = 0.0.0.0/0\nEndpoint = 127.0.0.1:9000\nPersistentKeepalive = 25\n")
	if err != nil {
		t.Fatal(err)
	}
	b, err := BuildConfig(ep, DefaultSettings(), "127.0.0.1:9090", "")
	if err != nil || !strings.Contains(string(b), `"endpoints"`) || !strings.Contains(string(b), "10.68.0.5/32") {
		t.Fatal(string(b))
	}
}

func TestDescAndBalancer(t *testing.T) {
	body := "vless://u@a.b:443?security=tls#%F0%9F%87%A9%F0%9F%87%AA%20DE?serverDescription=" + base64.StdEncoding.EncodeToString([]byte("Быстрый")) + "\n"
	r := ParseContent(body)
	if len(r.Servers) != 1 || r.Servers[0].Desc != "Быстрый" || r.Servers[0].Name != "🇩🇪 DE" {
		t.Fatalf("%+v", r.Servers)
	}
	if m := DescMap(base64.StdEncoding.EncodeToString([]byte(body))); m["🇩🇪 DE"] != "Быстрый" {
		t.Fatal(m)
	}
	j := `{"outbounds":[{"type":"urltest","tag":"⚡️ Auto","outbounds":["A","B"]},{"type":"vless","tag":"A","server":"a","server_port":1,"uuid":"11111111-2222-3333-4444-555555555555"},{"type":"trojan","tag":"B","server":"b","server_port":2,"password":"p"}]}`
	r = ParseContent(j)
	if len(r.Servers) != 3 || r.Servers[0].Type != BalancerLabel || len(r.Servers[0].Members) != 2 {
		t.Fatalf("%+v", r.Servers)
	}
	var ob map[string]any
	json.Unmarshal(r.Servers[0].Outbound, &ob)
	rules := t.TempDir()
	for _, n := range []string{"geoip-ru.srs", "geosite-category-ru.srs", "geosite-category-ads-all.srs"} {
		os.WriteFile(filepath.Join(rules, n), []byte("x"), 0o644)
	}
	b, err := BuildConfig(ob, DefaultSettings(), "127.0.0.1:9090", rules)
	if err != nil || !strings.Contains(string(b), `"urltest"`) || !strings.Contains(string(b), "geoip-ru") {
		t.Fatal(err, string(b))
	}
}
