#!/usr/bin/env bash
# Check a release APK the way the OnePlus installer will: v2+v3 signature,
# 16 KB zip alignment of stored native libraries, and badging (ABI, sdk, version).
set -euo pipefail
APK="${1:?apk}"
SDK="${ANDROID_HOME:-/workspace/tools/sdk}"
BT="$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
echo "== $(basename "$APK") $(wc -c < "$APK") bytes =="
"$BT/apksigner" verify --verbose --print-certs "$APK"
"$BT/zipalign" -c -P 16 -v 4 "$APK"
"$BT/aapt" dump badging "$APK" | awk '/^package:|^sdkVersion:|^targetSdkVersion:|^native-code:|^feature-group:/{print}'
python3 - "$APK" << 'PY'
import struct, sys, zipfile
apk = sys.argv[1]
z = zipfile.ZipFile(apk)
print("-- native entries --")
bad = False
for i in z.infolist():
    if not i.filename.startswith("lib/") or not i.filename.endswith(".so"):
        continue
    kind = "stored" if i.compress_type == zipfile.ZIP_STORED else "compressed"
    # local header is 30 bytes + name + extra; data offset must be 16 KB aligned when stored
    print(f"{i.filename} {kind} unpacked={i.file_size} packed={i.compress_size}")
    if i.compress_type != zipfile.ZIP_STORED:
        print("  FAIL compressed native lib")
        bad = True
        continue
    data = z.read(i.filename)
    if data[:4] != b"\x7fELF":
        print("  not ELF")
        continue
    cls = data[4]
    if cls == 2:
        phoff, phsz, phn = struct.unpack_from("<Q", data, 32)[0], struct.unpack_from("<H", data, 54)[0], struct.unpack_from("<H", data, 56)[0]
        def ph(j):
            return struct.unpack_from("<IIQQQQQQ", data, phoff + j * phsz)
    else:
        phoff, phsz, phn = struct.unpack_from("<I", data, 28)[0], struct.unpack_from("<H", data, 42)[0], struct.unpack_from("<H", data, 44)[0]
        def ph(j):
            t, off, va, pa, fsz, msz, fl, al = struct.unpack_from("<IIIIIIII", data, phoff + j * phsz)
            return t, fl, off, va, pa, fsz, msz, al
    aligns = [ph(j)[7] for j in range(phn) if ph(j)[0] == 1]
    need = 16384 if "/arm64" in i.filename or "/x86_64" in i.filename else 4096
    ok = all(a >= need and a % need == 0 for a in aligns) if aligns else False
    print(f"  LOAD align={aligns} need>={need} {'OK' if ok else 'FAIL'}")
    if not ok:
        bad = True
if bad:
    sys.exit(1)
PY
