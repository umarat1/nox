package core

import "strings"

// toASCII converts an IDN ("президент.рф") to its xn-- form (RFC 3492), label by label.
func toASCII(d string) string {
	labels := strings.Split(d, ".")
	for i, l := range labels {
		ascii := true
		for _, r := range l {
			if r >= 0x80 {
				ascii = false
				break
			}
		}
		if !ascii {
			labels[i] = "xn--" + punyEncode(l)
		}
	}
	return strings.Join(labels, ".")
}

func punyEncode(s string) string {
	const base, tmin, tmax, skew, damp = 36, 1, 26, 38, 700
	in := []rune(s)
	var out []byte
	for _, r := range in {
		if r < 0x80 {
			out = append(out, byte(r))
		}
	}
	b := len(out)
	h := b
	if b > 0 {
		out = append(out, '-')
	}
	digit := func(d int) byte {
		if d < 26 {
			return byte('a' + d)
		}
		return byte('0' + d - 26)
	}
	adapt := func(delta, n int, first bool) int {
		if first {
			delta /= damp
		} else {
			delta /= 2
		}
		delta += delta / n
		k := 0
		for delta > ((base-tmin)*tmax)/2 {
			delta /= base - tmin
			k += base
		}
		return k + (base-tmin+1)*delta/(delta+skew)
	}
	n, delta, bias := 0x80, 0, 72
	for h < len(in) {
		m := int(^uint(0) >> 1)
		for _, r := range in {
			if int(r) >= n && int(r) < m {
				m = int(r)
			}
		}
		delta += (m - n) * (h + 1)
		n = m
		for _, r := range in {
			if int(r) < n {
				delta++
			}
			if int(r) == n {
				q := delta
				for k := base; ; k += base {
					t := k - bias
					if t < tmin {
						t = tmin
					} else if t > tmax {
						t = tmax
					}
					if q < t {
						break
					}
					out = append(out, digit(t+(q-t)%(base-t)))
					q = (q - t) / (base - t)
				}
				out = append(out, digit(q))
				bias = adapt(delta, h+1, h == b)
				delta = 0
				h++
			}
		}
		delta++
		n++
	}
	return string(out)
}
