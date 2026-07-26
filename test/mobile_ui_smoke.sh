#!/bin/sh
set -eu

mobile_view=$1
web_page=$2

grep -q "simultaneousGesture" "$mobile_view"
if grep -q "highPriorityGesture" "$mobile_view"; then
  echo "Sidebar gestures must not block vertical WebView scrolling" >&2
  exit 1
fi

grep -q "overflow-y: auto" "$web_page"
grep -q -- "-webkit-overflow-scrolling: touch" "$web_page"
