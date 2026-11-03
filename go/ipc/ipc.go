// Package ipc exposes engine.App to the Flutter UI over loopback HTTP JSON-RPC.
//
// Why loopback HTTP instead of a named pipe: Dart's dart:io has no named-pipe client, while
// HTTP works unchanged on Windows, macOS (to a helper) and in tests. Access control: the
// listener binds 127.0.0.1 only, a 256-bit token is required in X-Nox-Token, and the token
// lives in ipc.json whose ACL grants read only to SYSTEM, Administrators and local Users
// (same audience a named pipe with an "IU" ACE would have). No CORS headers are sent, so web
// pages cannot read responses or learn the token.
package ipc

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"time"

	"nox/engine"
)

type Info struct {
	Port    int    `json:"port"`
	Token   string `json:"token"`
	PID     int    `json:"pid"`
	Version string `json:"version"`
}

var hidden = map[string]bool{"Start": true, "Shutdown": true}

type Server struct {
	app   *engine.App
	token string
	srv   *http.Server
	ln    net.Listener
	meth  map[string]reflect.Value
}

func New(app *engine.App) *Server {
	s := &Server{app: app, meth: map[string]reflect.Value{}}
	v := reflect.ValueOf(app)
	t := v.Type()
	for i := 0; i < t.NumMethod(); i++ {
		m := t.Method(i)
		if !hidden[m.Name] {
			s.meth[m.Name] = v.Method(i)
		}
	}
	return s
}

// Methods lists callable names (for tests / the Dart client generator).
func (s *Server) Methods() []string {
	var out []string
	for k := range s.meth {
		out = append(out, k)
	}
	return out
}

// Listen binds 127.0.0.1:port (0 = random) and writes ipc.json into dir.
func (s *Server) Listen(dir string, port int) (Info, error) {
	b := make([]byte, 32)
	rand.Read(b)
	s.token = hex.EncodeToString(b)
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return Info{}, err
	}
	s.ln = ln
	info := Info{Port: ln.Addr().(*net.TCPAddr).Port, Token: s.token, PID: os.Getpid(), Version: engine.Version}
	j, _ := json.Marshal(info)
	p := filepath.Join(dir, "ipc.json")
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, j, 0o644); err != nil {
		return info, err
	}
	if err := os.Rename(tmp, p); err != nil {
		return info, err
	}
	if err := restrictInfoFile(p); err != nil {
		return info, fmt.Errorf("ipc.json ACL: %w", err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"ok":true,"version":%q}`, engine.Version)
	})
	mux.HandleFunc("/rpc", s.rpc)
	s.srv = &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	return info, nil
}

func (s *Server) Serve() error { return s.srv.Serve(s.ln) }
func (s *Server) Close()       { s.srv.Close() }

type req struct {
	M string            `json:"m"`
	A []json.RawMessage `json:"a"`
}

func (s *Server) rpc(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		http.Error(w, `{"e":"POST only"}`, 405)
		return
	}
	if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Nox-Token")), []byte(s.token)) != 1 {
		http.Error(w, `{"e":"forbidden"}`, 403)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 8<<20))
	if err != nil {
		return
	}
	var q req
	if json.Unmarshal(body, &q) != nil {
		http.Error(w, `{"e":"bad json"}`, 400)
		return
	}
	res, err := s.Call(q.M, q.A)
	if err != nil {
		w.WriteHeader(400)
		json.NewEncoder(w).Encode(map[string]string{"e": err.Error()})
		return
	}
	json.NewEncoder(w).Encode(map[string]any{"r": res})
}

// Call invokes an App method with JSON arguments.
func (s *Server) Call(name string, args []json.RawMessage) (res any, err error) {
	m, ok := s.meth[name]
	if !ok {
		return nil, errors.New("unknown method " + name)
	}
	t := m.Type()
	if len(args) != t.NumIn() {
		return nil, fmt.Errorf("%s: want %d args, got %d", name, t.NumIn(), len(args))
	}
	in := make([]reflect.Value, t.NumIn())
	for i := range in {
		p := reflect.New(t.In(i))
		if err := json.Unmarshal(args[i], p.Interface()); err != nil {
			return nil, fmt.Errorf("%s arg %d: %v", name, i, err)
		}
		in[i] = p.Elem()
	}
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("%s: panic: %v", name, r)
		}
	}()
	out := m.Call(in)
	// a trailing error result (func() error, func() (T, error)) is the call's error
	if n := len(out); n > 0 && t.Out(n-1) == errType {
		if e, _ := out[n-1].Interface().(error); e != nil {
			return nil, e
		}
		out = out[:n-1]
	}
	if len(out) == 0 {
		return nil, nil
	}
	return out[0].Interface(), nil
}

var errType = reflect.TypeOf((*error)(nil)).Elem()
