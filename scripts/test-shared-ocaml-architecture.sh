#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
failure=0

fail() {
  echo "error: $*" >&2
  failure=1
}

for path in \
  apple \
  android \
  native \
  src \
  ocaml_demo_android.opam \
  ocaml_demo_apple.opam \
  ocaml_demo_native.opam
do
  [[ ! -e $repo_root/$path ]] || fail "legacy path still exists: $path"
done

[[ ! -e $repo_root/web/demo/react_runtime.js ]] \
  || fail "Web React UI must be written in OCaml, not a JavaScript renderer"

if ! rg --fixed-strings --quiet \
  '[@@mel.module "react"]' \
  "$repo_root/web/demo/main.ml"
then
  fail "Web OCaml must import React through Melange"
fi

for path in \
  examples/shared/ocaml_demo_model.ml \
  examples/shared/ocaml_demo_rpc.ml \
  mobile/Sources/OCamlDemo/OCamlDemoView.swift \
  web/demo/main.ml \
  scripts/build-desktop-macos.sh
do
  [[ -f $repo_root/$path ]] || fail "maintained platform path is missing: $path"
done

if ! rg --fixed-strings --quiet \
  "(libraries ocaml_demo_model)" \
  "$repo_root/web/demo/dune"
then
  fail "Web must depend directly on the shared OCaml model"
fi

if rg --quiet \
  "ocaml_demo_(android|apple|native)" \
  "$repo_root" \
  --glob '!_build/**' \
  --glob '!mobile/.build/**' \
  --glob '!*test-shared-ocaml-architecture.sh'
then
  fail "legacy platform OCaml packages are still referenced"
fi

if rg --quiet \
  "type action[[:space:]]*=" \
  "$repo_root/mobile" \
  "$repo_root/web"
then
  fail "platform code must not define a second business action type"
fi

exit "$failure"
