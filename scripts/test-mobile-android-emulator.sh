#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
adb="$android_home/platform-tools/adb"
apk="$repo_root/mobile/.build/Android/app/outputs/apk/debug/app-debug.apk"
package_name=com.logseq.ocamldemo
activity=ocaml.demo.MainActivity
xml_device=/sdcard/ocaml-demo-ui.xml
xml_host="$repo_root/_build/android-emulator-ui.xml"

die() {
  echo "error: $*" >&2
  exit 1
}

[[ -x $adb ]] || die "adb was not found: $adb"
[[ -f $apk ]] || die "APK was not found: $apk"
"$adb" get-state >/dev/null 2>&1 || die "no Android emulator is connected"

"$adb" install -r "$apk" >/dev/null
"$adb" shell am force-stop "$package_name"
"$adb" shell am start -W -n "$package_name/$activity" >/dev/null

dump_ui() {
  "$adb" shell uiautomator dump "$xml_device" >/dev/null
  "$adb" pull "$xml_device" "$xml_host" >/dev/null
}

for _ in {1..20}; do
  dump_ui
  if grep -q 'text="0" resource-id="label.counter.value"' "$xml_host"; then
    break
  fi
  sleep 1
done
grep -q 'text="0" resource-id="label.counter.value"' "$xml_host" \
  || die "counter did not render its initial OCaml value"

increment_node=$(grep -o '<node[^>]*resource-id="button.counter.increment"[^>]*/>' "$xml_host")
[[ -n $increment_node ]] || die "increment button was not found"

bounds=$(printf '%s\n' "$increment_node" \
  | sed -E 's/.*bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]".*/\1 \2 \3 \4/')
read -r left top right bottom <<<"$bounds"
x=$(((left + right) / 2))
y=$(((top + bottom) / 2))
"$adb" shell input tap "$x" "$y"

for _ in {1..10}; do
  dump_ui
  if grep -q 'text="1" resource-id="label.counter.value"' "$xml_host"; then
    echo "Verified Android Compose -> JNA -> OCaml reducer: 0 -> 1"
    exit 0
  fi
  sleep 1
done

die "counter did not update through the OCaml core"
