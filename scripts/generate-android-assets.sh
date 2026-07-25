#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
asset_dir="$repo_root/android/app/src/main/assets"
opam_switch=${OCAML_DEMO_ANDROID_OPAM_SWITCH:-${OCAML_DEMO_OPAM_SWITCH:-$repo_root}}

mkdir -p "$asset_dir"

for demo_id in counter todo search; do
  opam exec --switch="$opam_switch" -- \
    dune exec "$repo_root/android/examples/export_counter_json.exe" -- "$demo_id" \
    > "$asset_dir/ocaml_demo_${demo_id}.json"
  echo "Generated $asset_dir/ocaml_demo_${demo_id}.json"
done
