package sstp

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

func lookupDoH(host string) string {
	cl := &http.Client{Timeout: 8 * time.Second}
	req, _ := http.NewRequest("GET", "https://1.1.1.1/dns-query?name="+host+"&type=A", nil)
	req.Header.Set("Accept", "application/dns-json")
	r, err := cl.Do(req)
	if err != nil {
		return ""
	}
	defer r.Body.Close()
	var j struct {
		Answer []struct {
			Type int    `json:"type"`
			Data string `json:"data"`
		}
	}
	if json.NewDecoder(r.Body).Decode(&j) != nil {
		return ""
	}
	for _, a := range j.Answer {
		if a.Type == 1 {
			return a.Data
		}
	}
	_ = fmt.Sprintf
	return ""
}
