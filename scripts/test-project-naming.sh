#!/usr/bin/env bash

set -euo pipefail

repository_root=$(git rev-parse --show-toplevel)
expected_repository_name="ocaml-demo"
legacy_name="bon""sai"
failure=0

if [[ "$(basename "$repository_root")" != "$expected_repository_name" ]]; then
  echo "Repository directory must be named $expected_repository_name" >&2
  failure=1
fi

while IFS= read -r path; do
  [[ -e "$repository_root/$path" ]] || continue

  lower_path=$(printf '%s\n' "$path" | tr '[:upper:]' '[:lower:]')
  if [[ "$lower_path" == *"$legacy_name"* ]]; then
    echo "Legacy name remains in path: $path" >&2
    failure=1
  fi

  if rg --ignore-case --files-with-matches "$legacy_name" -- "$repository_root/$path" \
    >/dev/null 2>&1; then
    echo "Legacy name remains in file: $path" >&2
    failure=1
  fi
done < <(git -C "$repository_root" ls-files --cached --others --exclude-standard)

require_text() {
  local path=$1
  local expected=$2

  if ! rg --fixed-strings --quiet "$expected" "$repository_root/$path"; then
    echo "Expected '$expected' in $path" >&2
    failure=1
  fi
}

require_text "mobile/Darwin/Info.plist" "<string>OCaml Demo</string>"
require_text "mobile/Darwin/Info.macos.plist" "<string>OCaml Demo</string>"
require_text "mobile/Android/app/src/main/AndroidManifest.xml" 'android:label="OCaml Demo"'
require_text "dune-project" "(name ocaml_demo)"
require_text "mobile/Package.swift" 'name: "ocaml-demo-mobile"'
require_text "mobile/Android/settings.gradle.kts" 'rootProject.name = "ocaml.demo"'
require_text "web/demo/main.ml" "module Model = Ocaml_demo_model"

exit "$failure"
