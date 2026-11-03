package engine

import (
	"encoding/json"
	"testing"
)

func TestParseUpdateTopLevelAndroid(t *testing.T) {
	raw := []byte(`{"versionCode":109,"versionName":"1.0.9","url":"https://iji.by/dl/u.apk","url_arm64":"https://iji.by/dl/a.apk","sha256":"aa","sha256_arm64":"bb","notes":"n"}`)
	var m map[string]json.RawMessage
	json.Unmarshal(raw, &m)
	AndroidABI = "arm64-v8a"
	u := &UpdateInfo{Version: "1.0.9", Code: 109, URL: "https://iji.by/dl/u.apk", SHA256: "aa", Notes: "n"}
	pickAndroidURL(u, m)
	if u.URL != "https://iji.by/dl/a.apk" || u.SHA256 != "bb" {
		t.Fatalf("%+v", u)
	}
	AndroidABI = "armeabi-v7a"
	u = &UpdateInfo{Version: "1.0.9", Code: 109, URL: "https://iji.by/dl/u.apk", SHA256: "aa"}
	m2 := map[string]json.RawMessage{}
	json.Unmarshal([]byte(`{"url_armv7":"https://iji.by/dl/v.apk","sha256_armv7":"cc"}`), &m2)
	for k, v := range m2 {
		m[k] = v
	}
	pickAndroidURL(u, m)
	if u.URL != "https://iji.by/dl/v.apk" || u.SHA256 != "cc" {
		t.Fatalf("armv7 %+v", u)
	}
	if !verLess("1.0.5", "1.0.9") || verLess("1.0.9", "1.0.9") {
		t.Fatal("verLess")
	}
	ft := flattenTop(m)
	var u2 UpdateInfo
	if json.Unmarshal(ft, &u2) != nil || u2.Version != "1.0.9" {
		t.Fatalf("flatten %+v", u2)
	}
}
