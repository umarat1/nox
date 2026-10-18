package engine

import (
	"strings"
	"sync/atomic"
)

// CaptchaUI: the platform can show VK's captcha page (Android WebView). When false, qWDTT's
// requests for a WebView are declined at once so its own solver chain moves on.
var CaptchaUI = false

// CaptchaReq is a pending VK captcha (qWDTT asked for a manual solve). The UI opens URL in a
// WebView, takes success_token from VK's captchaNotRobot.check reply and calls SolveCaptcha.
type CaptchaReq struct {
	ID  int64  `json:"id"`
	URL string `json:"url"`
}

var captchaSeq int64

// qwdttCaptchaLine handles "CAPTCHA_SOLVE|mode|redirect_uri|session_token" from qwdtt.
// Returns true when the line was consumed (it is never logged: it carries session data).
func (a *App) qwdttCaptchaLine(l string) bool {
	if !strings.HasPrefix(l, "CAPTCHA_SOLVE|") {
		return false
	}
	parts := strings.SplitN(strings.TrimPrefix(l, "CAPTCHA_SOLVE|"), "|", 3)
	mode, uri := "selected", ""
	switch len(parts) {
	case 3:
		mode, uri = parts[0], parts[1]
	case 2:
		uri = parts[0]
	}
	if !CaptchaUI || mode == "auto" || !strings.HasPrefix(uri, "https://") {
		// no headless solver here: let qwdtt continue with its next method
		a.qwdttWrite("CAPTCHA_RESULT|error:unsupported")
		return true
	}
	a.mu.Lock()
	a.captcha = &CaptchaReq{ID: atomic.AddInt64(&captchaSeq, 1), URL: uri}
	a.mu.Unlock()
	a.log("qWDTT: VK просит пройти проверку «я не робот»")
	return true
}

func (a *App) qwdttWrite(line string) {
	a.mu.Lock()
	w := a.qwStdin
	a.mu.Unlock()
	if w != nil {
		w.Write([]byte(line + "\n"))
	}
}

// SolveCaptcha passes the WebView result (success_token, or "error:…") back to qWDTT.
func (a *App) SolveCaptcha(id int64, result string) {
	a.mu.Lock()
	c := a.captcha
	if c == nil || c.ID != id {
		a.mu.Unlock()
		return
	}
	a.captcha = nil
	a.mu.Unlock()
	result = strings.TrimSpace(strings.ReplaceAll(result, "\n", ""))
	if result == "" {
		result = "error:empty"
	}
	a.qwdttWrite("CAPTCHA_RESULT|" + result)
	if strings.HasPrefix(result, "error:") {
		a.log("qWDTT: проверка не пройдена (" + strings.TrimPrefix(result, "error:") + ")")
	} else {
		a.log("qWDTT: проверка пройдена")
	}
}
