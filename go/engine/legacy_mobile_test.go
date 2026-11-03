package engine

import "testing"

func TestImportAndroidLegacy(t *testing.T) {
	d := t.TempDir()
	a := NewApp(d, d)
	j := `{"servers":[
	 {"id":"a","name":"DE","protocol":"VLESS","host":"de.x","port":443,"outbound":{"type":"vless","tag":"p","server":"de.x","server_port":443,"uuid":"u"},"subscriptionId":"s1","latencyMs":55},
	 {"id":"b","name":"X","protocol":"Xray","host":"x","port":1,"outbound":{"type":"_xray"},"subscriptionId":"s1"},
	 {"id":"c","name":"Q","protocol":"qWDTT","host":"q","port":1,"outbound":"{\"type\":\"_qwdtt\",\"peer\":\"1.2.3.4:56000\"}"}],
	"subscriptions":[{"id":"s1","name":"iji.by","url":"https://iji.by/sub/x","updatedAt":1760000000000,"expire":1790000000,"total":100,"announce":"hi"}],
	"settings":{"bypassRussia":false,"theme":"light","mtu":1500}}`
	if !a.ImportLegacy(j) {
		t.Fatal("import failed")
	}
	st := a.GetState()
	if len(st.Servers) != 2 || st.Servers[0].Type != "VLESS" || st.Servers[1].Type != "qWDTT" || st.Servers[0].Ping != 55 {
		t.Fatalf("%+v", st.Servers)
	}
	if len(st.Subs) != 1 || st.Subs[0].Updated != 1760000000 || st.Subs[0].Announce != "hi" {
		t.Fatalf("%+v", st.Subs)
	}
	if st.Settings.DirectRU || st.Settings.Theme != "light" || st.Settings.MTU != 1500 {
		t.Fatalf("%+v", st.Settings)
	}
}
