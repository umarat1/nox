package noxproto

import (
	"crypto/rand"
	"encoding/binary"
	"time"
)

// Profiles describe how large each inner frame should look.
// browse: short request/response sizes, like JSON API calls.
// video: multi-kilobyte chunks, like a media segment.
// mixed: both, so a long session is not a single flat size.
const (
	ProfileBrowse = "browse"
	ProfileVideo  = "video"
	ProfileMixed  = "mixed"
)

func normalizeProfile(p string) string {
	switch p {
	case ProfileBrowse, ProfileVideo, ProfileMixed:
		return p
	default:
		return ProfileMixed
	}
}

func defaultJitter(profile string) time.Duration {
	switch normalizeProfile(profile) {
	case ProfileBrowse:
		return 15 * time.Millisecond
	case ProfileVideo:
		return 6 * time.Millisecond
	default:
		return 10 * time.Millisecond
	}
}

// sampleLen picks a padded plaintext size for one frame.
// The sizes are chosen so that, once HTTP/2 or HTTP/3 and TLS add a few
// bytes of header, the outer records are not a single constant length.
func sampleLen(profile string) int {
	switch normalizeProfile(profile) {
	case ProfileBrowse:
		return pick([]int{128, 256, 384, 512, 700, 1024, 1400}, []int{3, 4, 3, 3, 2, 2, 1})
	case ProfileVideo:
		return pick([]int{4096, 8192, 12000, 16384}, []int{1, 3, 3, 2})
	default:
		return pick([]int{256, 512, 1400, 4096, 8192, 16384}, []int{2, 2, 2, 2, 2, 1})
	}
}

func pick(sizes, weights []int) int {
	sum := 0
	for _, w := range weights {
		sum += w
	}
	n := int(randUint32() % uint32(sum))
	for i, w := range weights {
		if n < w {
			return sizes[i]
		}
		n -= w
	}
	return sizes[len(sizes)-1]
}

func randUint32() uint32 {
	var b [4]byte
	_, _ = rand.Read(b[:])
	return binary.BigEndian.Uint32(b[:])
}

// jitter sleeps a random duration in [0, max). max <= 0 disables it.
func jitter(max time.Duration) {
	if max <= 0 {
		return
	}
	d := time.Duration(randUint32() % uint32(max))
	time.Sleep(d)
}
