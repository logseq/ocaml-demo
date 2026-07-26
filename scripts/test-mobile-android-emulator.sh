#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
adb="$android_home/platform-tools/adb"
xml_device=/sdcard/ocaml-demo-window.xml
xml_host=$(mktemp)

die() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  rm -f "$xml_host"
}
trap cleanup EXIT

[[ -x $adb ]] || die "adb was not found at $adb"
"$adb" shell rm -f "$xml_device"
"$adb" shell uiautomator dump "$xml_device" >/dev/null
"$adb" pull "$xml_device" "$xml_host" >/dev/null

grep -q 'resource-id="button.sidebar"' "$xml_host" \
  || die "the mobile shell did not render"
grep -q 'text="Journals"' "$xml_host" \
  || die "the Journals screen did not render"
