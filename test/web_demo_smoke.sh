#!/bin/sh
set -eu

main=$1

test -s "$main"
grep -q "react-dom/client" "$main"
grep -q "createRoot" "$main"
grep -q "Journals" "$main"
grep -q "Tasks" "$main"
grep -q "Indent_block" "$main"
grep -q "insertSibling" "$main"
grep -q "editor-toolbar" "$main"
grep -q "M19 12H5" "$main"
if grep -q '\\xe2\\x86' "$main"; then
  echo "Web UI icons must not rely on OCaml UTF-8 byte strings" >&2
  exit 1
fi
