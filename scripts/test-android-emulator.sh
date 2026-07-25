#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
adb="$android_home/platform-tools/adb"
emulator="$android_home/emulator/emulator"
avd_name=${OCAML_DEMO_ANDROID_AVD:-Medium_Phone_API_36.1}
apk="$repo_root/android/app/build/outputs/apk/debug/app-debug.apk"
screenshot=${OCAML_DEMO_ANDROID_SCREENSHOT:-/tmp/ocaml-demo.png}
before_xml=${OCAML_DEMO_ANDROID_BEFORE_XML:-/tmp/ocaml-demo-before.xml}
after_xml=${OCAML_DEMO_ANDROID_AFTER_XML:-/tmp/ocaml-demo-after.xml}
todo_xml=${OCAML_DEMO_ANDROID_TODO_XML:-/tmp/ocaml-demo-todo.xml}
search_xml=${OCAML_DEMO_ANDROID_SEARCH_XML:-/tmp/ocaml-demo-search.xml}

dump_ui() {
  local output=$1
  "$adb" shell uiautomator dump /sdcard/ocaml-demo-ui.xml >/dev/null
  "$adb" pull /sdcard/ocaml-demo-ui.xml "$output" >/dev/null
}

tap_text() {
  local text=$1
  local xml=$2
  local point
  point=$(
    OCAML_DEMO_TAP_TEXT=$text perl -ne '
      my $text = $ENV{"OCAML_DEMO_TAP_TEXT"};
      if (/text="\Q$text\E"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/) {
        print int(($1 + $3) / 2) . " " . int(($2 + $4) / 2);
        exit;
      }
    ' "$xml"
  )
  if [[ -z "$point" ]]; then
    echo "Could not find tappable text '$text' in $xml" >&2
    exit 1
  fi
  "$adb" shell input tap $point
}

assert_text() {
  local text=$1
  local xml=$2
  if ! grep -q "text=\"$text\"" "$xml"; then
    echo "Expected text '$text' in $xml" >&2
    exit 1
  fi
}

if [[ ! -x "$adb" ]]; then
  echo "Missing adb at $adb" >&2
  exit 1
fi

if [[ ! -x "$emulator" ]]; then
  echo "Missing emulator at $emulator" >&2
  exit 1
fi

if [[ ! -f "$apk" ]]; then
  echo "Missing APK at $apk. Run: cd android && ./gradlew :app:assembleDebug" >&2
  exit 1
fi

booted_device=$("$adb" devices | awk '$2 == "device" { print $1; exit }')
if [[ -z "$booted_device" ]]; then
  log_file=${OCAML_DEMO_ANDROID_EMULATOR_LOG:-/tmp/ocaml-demo-emulator.log}
  emulator_args=(
    "@$avd_name"
    -no-snapshot
    -gpu swiftshader_indirect
    -no-audio
    -no-boot-anim
    -no-window
  )
  if [[ "${OCAML_DEMO_ANDROID_WIPE_DATA:-0}" == "1" ]]; then
    emulator_args+=(-wipe-data)
  fi
  "$emulator" "${emulator_args[@]}" > "$log_file" 2>&1 &
  emulator_pid=$!
  trap 'kill "$emulator_pid" 2>/dev/null || true' EXIT

  for _ in {1..60}; do
    booted_device=$("$adb" devices | awk '$2 == "device" { print $1; exit }')
    boot_completed=$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
    if [[ -n "$booted_device" && "$boot_completed" == "1" ]]; then
      break
    fi
    sleep 5
  done
else
  boot_completed=$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
fi

if [[ -z "$booted_device" || "$boot_completed" != "1" ]]; then
  echo "No booted emulator detected for $avd_name" >&2
  exit 1
fi

"$adb" install -r "$apk"
"$adb" shell am force-stop com.logseq.ocaml_demoandroid
"$adb" shell am start -W -n com.logseq.ocaml_demoandroid/.MainActivity >/dev/null
for _ in {1..20}; do
  sleep 2
  dump_ui "$before_xml"
  if grep -q 'text="Counter"' "$before_xml"; then
    break
  fi
  if grep -q 'text="Wait"' "$before_xml"; then
    tap_text "Wait" "$before_xml"
  fi
done
assert_text "Counter" "$before_xml"
assert_text "Todo" "$before_xml"
assert_text "Search" "$before_xml"
assert_text "0" "$before_xml"

tap_text "Increment" "$before_xml"
sleep 1
dump_ui "$after_xml"
assert_text "1" "$after_xml"

tap_text "Todo" "$after_xml"
sleep 1
dump_ui "$todo_xml"
assert_text "New task" "$todo_xml"
assert_text "Add" "$todo_xml"

tap_text "Search" "$todo_xml"
sleep 1
dump_ui "$search_xml"
assert_text "Search" "$search_xml"
assert_text "Today" "$search_xml"
assert_text "Tasks" "$search_xml"
assert_text "Settings" "$search_xml"

"$adb" exec-out screencap -p > "$screenshot"

echo "Installed $apk on $booted_device"
echo "Verified Android demo parity tabs and native click dispatch: 0 -> 1"
echo "Captured $screenshot"
