#!/usr/bin/env bash
set -euo pipefail

APK="${1:-LocalShare-1.4.2-Android.apk}"
PACKAGE="com.mographiccode.local_share"
ACTIVITY="$PACKAGE/.MainActivity"

if [[ ! -s "$APK" ]]; then
  echo "APK not found: $APK" >&2
  exit 1
fi

installed=0
for attempt in 1 2 3; do
  echo "APK install attempt $attempt"
  if adb install --no-streaming -r "$APK"; then
    installed=1
    break
  fi
  adb kill-server || true
  adb start-server
  adb wait-for-device
  sleep 5
done

if [[ "$installed" != "1" ]]; then
  echo "Unable to install APK after three attempts" >&2
  exit 1
fi

adb shell pm grant "$PACKAGE" android.permission.POST_NOTIFICATIONS || true
adb logcat -c
adb shell am force-stop "$PACKAGE" || true
adb shell am start -n "$ACTIVITY"
sleep 15

pid="$(adb shell pidof "$PACKAGE" | tr -d '\r' || true)"
if [[ -z "$pid" ]]; then
  echo "LocalShare process is not running after launch" >&2
  adb logcat -d | tail -n 400 || true
  exit 1
fi

echo "LocalShare PID: $pid"
adb shell dumpsys window | grep -q "$PACKAGE"
adb exec-out screencap -p > LocalShare-Android-startup.png

python - <<'PY'
from PIL import Image, ImageStat

path = 'LocalShare-Android-startup.png'
im = Image.open(path).convert('RGB')
w, h = im.size
crop = im.crop((int(w * .08), int(h * .10), int(w * .92), int(h * .88)))
px = list(crop.getdata())
non_white = sum(1 for r, g, b in px if min(r, g, b) < 238)
ratio = non_white / max(1, len(px))
stat = ImageStat.Stat(crop)
print(f'startup screenshot={im.size}, non-white ratio={ratio:.4f}, mean={stat.mean}')
if ratio < 0.03:
    raise SystemExit('Startup UI appears blank/white')
PY

adb logcat --pid="$pid" -d > LocalShare-Android-logcat.txt || true
if grep -Eiq 'FATAL EXCEPTION|Unhandled Exception|Dart Error' LocalShare-Android-logcat.txt; then
  echo "Fatal runtime error detected in LocalShare logcat" >&2
  cat LocalShare-Android-logcat.txt
  exit 1
fi

if ! adb shell dumpsys activity services "$PACKAGE" | grep -q LocalShareForegroundService; then
  echo "LocalShareForegroundService is not running after launch" >&2
  adb shell dumpsys activity services "$PACKAGE" || true
  exit 1
fi

adb shell input keyevent KEYCODE_HOME
sleep 8

if ! adb shell pidof "$PACKAGE" >/dev/null; then
  echo "LocalShare process died after moving to background" >&2
  exit 1
fi

if ! adb shell dumpsys activity services "$PACKAGE" | grep -q LocalShareForegroundService; then
  echo "LocalShareForegroundService stopped in background" >&2
  exit 1
fi

adb shell am force-stop "$PACKAGE"
echo "ANDROID_RUNTIME_SMOKE_OK"
