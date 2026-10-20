package core

import "testing"

func TestQwdttFatalCaptcha(t *testing.T) {
	if QwdttFatal("FATAL_CAPTCHA: all methods failed") == "" || QwdttFatal("VK API error error_code:29") == "" || QwdttFatal("ok line") != "" {
		t.Fatal("fatal mapping")
	}
}
