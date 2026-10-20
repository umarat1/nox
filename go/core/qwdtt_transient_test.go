package core

import "testing"

func TestQwdttTransient(t *testing.T) {
	for _, l := range []string{"VK error_code:29 rate", "FATAL_CAPTCHA", "flood control"} {
		if f := QwdttFatal(l); f == "" || !QwdttTransient(f) {
			t.Fatalf("%q should be transient fatal, got %q", l, f)
		}
	}
	if f := QwdttFatal("denied:deactivated"); f == "" || QwdttTransient(f) {
		t.Fatalf("deactivated must be hard fatal: %q", f)
	}
}
