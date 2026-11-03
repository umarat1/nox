package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// ChainType: client-side proxy chain (Exclave-style). Hop N dials through hop N-1 via sing-box "detour".
const ChainType = "_chain"
const ChainLabel = "Цепочка"

// MakeChain builds a chain server from 2-3 hops in order (first = entry).
func MakeChain(name string, hops []Server) (Server, error) {
	if len(hops) < 2 || len(hops) > 3 {
		return Server{}, errors.New("в цепочке должно быть 2–3 сервера")
	}
	var obs []json.RawMessage
	var names []string
	for _, h := range hops {
		if err := chainable(h); err != nil {
			return Server{}, err
		}
		obs = append(obs, h.Outbound)
		names = append(names, h.Name)
	}
	b, _ := json.Marshal(map[string]any{"type": ChainType, "outbounds": obs})
	if strings.TrimSpace(name) == "" {
		name = strings.Join(names, " → ")
	}
	return Server{Name: name, Type: ChainLabel, Host: hops[0].Host, Port: hops[0].Port, Outbound: b, Members: names}, nil
}

func chainable(h Server) error {
	var m map[string]any
	if err := json.Unmarshal(h.Outbound, &m); err != nil {
		return err
	}
	t, _ := m["type"].(string)
	switch {
	case IsXray(h.Outbound), IsExt(h.Outbound), IsFullTunnel(h.Outbound), t == "_qwdtt", h.Type == "qWDTT":
		return fmt.Errorf("«%s» (%s) нельзя поставить в цепочку", h.Name, h.Type)
	case t == BalancerType || t == ChainType || t == "wireguard" || t == "":
		return fmt.Errorf("«%s» (%s) нельзя поставить в цепочку", h.Name, h.Type)
	}
	return nil
}

// expandChain turns a _chain proxy into the final hop tagged "proxy" plus earlier hops c0..cN.
func expandChain(proxy map[string]any) (map[string]any, []any, error) {
	if proxy["type"] != ChainType {
		return proxy, nil, nil
	}
	arr, _ := proxy["outbounds"].([]any)
	if len(arr) < 2 {
		return nil, nil, errors.New("цепочка: мало серверов")
	}
	var extra []any
	prev := ""
	for i, x := range arr {
		m, ok := x.(map[string]any)
		if !ok {
			return nil, nil, errors.New("цепочка: неверный сервер")
		}
		if prev != "" {
			m["detour"] = prev
		}
		if i == len(arr)-1 {
			m["tag"] = "proxy"
			return m, extra, nil
		}
		t := fmt.Sprintf("c%d", i)
		m["tag"] = t
		extra = append(extra, m)
		prev = t
	}
	return nil, nil, errors.New("цепочка пуста")
}
