package engine

import (
	"bufio"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

// AdStats (2.4.0): DNS queries answered NXDOMAIN and connections rejected by the ad rules. Session counts since the
// current connection started; Total adds up over all connections (kept in state.json).
type AdStats struct {
	Session int64            `json:"session"`
	Total   int64            `json:"total"`
	BySrc   map[string]int64 `json:"bySrc"` // this session, by vendor (google, yandex, rutube, …)
}

// adMatchSrc parses a sing-box rule-match debug line and returns the ad vendor when the
// line is an ad rule blocking something: a DNS answer
// ("dns: match[2] domain_suffix=[…] => predefined(NXDOMAIN)") or a connection
// ("router: match[7] domain_suffix=[…] => reject"). "" otherwise.
func adMatchSrc(line string, sigs map[string]string) string {
	i := strings.Index(line, "match[")
	if i < 0 {
		return ""
	}
	j := strings.Index(line[i:], " => ")
	if j < 0 {
		return ""
	}
	act := line[i+j+4:]
	if !strings.HasPrefix(act, "predefined(") && !strings.HasPrefix(act, "reject") {
		return ""
	}
	rule := line[i : i+j]
	for src, sig := range sigs {
		if strings.Contains(rule, sig) {
			return src
		}
	}
	return ""
}

// noteAdBlock counts one blocked query/connection for a vendor.
func (a *App) noteAdBlock(src string) {
	a.mu.Lock()
	if a.adBySrc == nil {
		a.adBySrc = map[string]int64{}
	}
	a.adSession++
	a.p.AdsBlocked++
	a.adBySrc[src]++
	a.mu.Unlock()
}

// adCountLoop follows the core's log stream (clash API /logs, debug level; the stream works
// whatever log.level is, because the clash API makes the log observable) and counts the
// ad rules' NXDOMAIN answers and rejected connections (core.AdSigs).
func (a *App) adCountLoop(ctx context.Context, sigs map[string]string) {
	if len(sigs) == 0 {
		return
	}
	a.mu.Lock()
	a.adSession, a.adBySrc = 0, map[string]int64{}
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		a.save() // persist Total
		a.mu.Unlock()
	}()
	cl := &http.Client{Transport: &http.Transport{Proxy: nil}}
	lastSave := time.Now()
	for ctx.Err() == nil {
		req, _ := http.NewRequestWithContext(ctx, "GET", "http://"+a.clashAddr+"/logs?level=debug", nil)
		r, err := cl.Do(req)
		if err != nil {
			select {
			case <-ctx.Done():
				return
			case <-time.After(2 * time.Second):
			}
			continue
		}
		sc := bufio.NewScanner(r.Body)
		sc.Buffer(make([]byte, 64<<10), 4<<20)
		for sc.Scan() {
			var e struct {
				Payload string `json:"payload"`
			}
			if json.Unmarshal(sc.Bytes(), &e) != nil {
				continue
			}
			if src := adMatchSrc(e.Payload, sigs); src != "" {
				a.noteAdBlock(src)
				if time.Since(lastSave) > time.Minute {
					lastSave = time.Now()
					a.mu.Lock()
					a.save()
					a.mu.Unlock()
				}
			}
		}
		r.Body.Close()
	}
}

func (a *App) adStatsLocked() *AdStats {
	m := make(map[string]int64, len(a.adBySrc))
	for k, v := range a.adBySrc {
		m[k] = v
	}
	return &AdStats{a.adSession, a.p.AdsBlocked, m}
}

// ResetAdStats clears the counters (the «Сбросить» link under the counter).
func (a *App) ResetAdStats() {
	a.mu.Lock()
	a.adSession, a.adBySrc, a.p.AdsBlocked = 0, map[string]int64{}, 0
	a.save()
	a.mu.Unlock()
}
