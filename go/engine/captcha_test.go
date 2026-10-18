package engine

import (
	"bytes"
	"strings"
	"testing"
)

type wbuf struct{ bytes.Buffer }

func (*wbuf) Close() error { return nil }

func TestQwdttCaptcha(t *testing.T) {
	a := &App{}
	w := &wbuf{}
	a.qwStdin = w
	if a.qwdttCaptchaLine("[STREAM 1] hello") {
		t.Fatal("plain line consumed")
	}
	CaptchaUI = true
	defer func() { CaptchaUI = false }()
	// WBV Auto (headless in qWDTT's own app): declined at once
	if !a.qwdttCaptchaLine("CAPTCHA_SOLVE|auto|https://id.vk.com/not_robot_captcha?x=1|sess") || a.captcha != nil {
		t.Fatal("auto")
	}
	if !strings.Contains(w.String(), "CAPTCHA_RESULT|error:") {
		t.Fatal(w.String())
	}
	w.Reset()
	a.qwdttCaptchaLine("CAPTCHA_SOLVE|manual|https://id.vk.com/not_robot_captcha?x=2|sess")
	c := a.captcha
	if c == nil || c.URL != "https://id.vk.com/not_robot_captcha?x=2" {
		t.Fatalf("%+v", c)
	}
	a.SolveCaptcha(c.ID+1, "stale")
	if w.Len() != 0 || a.captcha == nil {
		t.Fatal("stale id answered")
	}
	a.SolveCaptcha(c.ID, "tok123")
	if w.String() != "CAPTCHA_RESULT|tok123\n" || a.captcha != nil {
		t.Fatal(w.String())
	}
}
