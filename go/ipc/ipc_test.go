package ipc

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"nox/engine"
)

func TestRPC(t *testing.T) {
	d := t.TempDir()
	app := engine.NewApp(d, d)
	s := New(app)
	info, err := s.Listen(d, 0)
	if err != nil {
		t.Fatal(err)
	}
	go s.Serve()
	defer s.Close()
	url := fmt.Sprintf("http://127.0.0.1:%d/rpc", info.Port)
	call := func(tok, m string, args ...any) (int, map[string]json.RawMessage) {
		raw := []json.RawMessage{}
		for _, a := range args {
			b, _ := json.Marshal(a)
			raw = append(raw, b)
		}
		b, _ := json.Marshal(map[string]any{"m": m, "a": raw})
		r, _ := http.NewRequest("POST", url, bytes.NewReader(b))
		r.Header.Set("X-Nox-Token", tok)
		resp, err := http.DefaultClient.Do(r)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var out map[string]json.RawMessage
		json.NewDecoder(resp.Body).Decode(&out)
		return resp.StatusCode, out
	}
	if c, _ := call("bad", "GetState"); c != 403 {
		t.Fatal("token not enforced", c)
	}
	c, out := call(info.Token, "Import", "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?security=tls&sni=a.b#%F0%9F%87%A9%F0%9F%87%AA%20Test")
	if c != 200 {
		t.Fatal(c, string(out["e"]))
	}
	c, out = call(info.Token, "GetState")
	var st engine.UIState
	json.Unmarshal(out["r"], &st)
	if c != 200 || len(st.Servers) != 1 || st.Version != engine.Version {
		t.Fatalf("%d %+v", c, st)
	}
	if c, _ := call(info.Token, "Shutdown"); c != 400 {
		t.Fatal("hidden method callable")
	}
	if c, _ := call(info.Token, "Select", st.Servers[0].ID); c != 200 {
		t.Fatal("select")
	}
}

// Engine methods shaped (T, error) must surface the error, not an empty T as success
// (a wrong pairing code showed «Отправлено на ТВ: 0 подписок, 0 серверов»).
func TestCallReturnsMethodError(t *testing.T) {
	d := t.TempDir()
	s := New(engine.NewApp(d, d))
	arg := func(v any) json.RawMessage { b, _ := json.Marshal(v); return b }
	r, err := s.Call("PairSend", []json.RawMessage{arg("nox://pair?h=bad"), arg(""), arg(engine.PairOpts{})})
	if err == nil {
		t.Fatalf("PairSend with a bad target: want error, got result %#v", r)
	}
	// PairStart (T, error) still returns its value on success
	r, err = s.Call("PairStart", nil)
	if err != nil {
		t.Fatal(err)
	}
	if info, ok := r.(engine.PairInfo); !ok || info.Port == 0 || len(info.Code) != 6 {
		t.Fatalf("PairStart result: %#v", r)
	}
	s.Call("PairStop", nil)
}
