#!/bin/sh
set -eu

main=$1

test -s "$main"
grep -q "react-dom/client" "$main"
grep -q "createRoot" "$main"
grep -q "Counter" "$main"
grep -q "Increment" "$main"
