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

if ! grep -Fq -- \
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

if ! grep -Fq -- \
  "(libraries ocaml_demo_model)" \
  "$repo_root/web/demo/dune"
then
  fail "Web must depend directly on the shared OCaml model"
fi

legacy_package_reference=0
while IFS= read -r -d '' path; do
  [[ $path != scripts/test-shared-ocaml-architecture.sh ]] || continue
  if grep -EIq -- "ocaml_demo_(android|apple|native)" "$repo_root/$path"; then
    legacy_package_reference=1
    break
  fi
done < <(git -C "$repo_root" ls-files -z --cached --others --exclude-standard)

if ((legacy_package_reference)); then
  fail "legacy platform OCaml packages are still referenced"
fi

platform_action_type=0
while IFS= read -r -d '' path; do
  if grep -EIq -- "type action[[:space:]]*=" "$repo_root/$path"; then
    platform_action_type=1
    break
  fi
done < <(
  git -C "$repo_root" ls-files -z --cached --others --exclude-standard \
    -- mobile web
)

if ((platform_action_type)); then
  fail "platform code must not define a second business action type"
fi

exit "$failure"
