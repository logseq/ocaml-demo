#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ocaml_version=${OCAML_DEMO_IOS_OCAML_VERSION:-5.5.0}
target=arm64-apple-ios17.0-simulator
target_prefix="$repo_root/_build/ios-toolchain/$target-$ocaml_version"
app="$repo_root/mobile/.build/OCamlDemo.app/OCamlDemo"
fake_bin=$(mktemp -d)

cleanup() {
  rm -rf "$fake_bin"
}
trap cleanup EXIT

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "error: iOS build invoked opam" >&2' \
  'exit 99' \
  >"$fake_bin/opam"
chmod +x "$fake_bin/opam"

PATH="$fake_bin:$PATH" "$repo_root/scripts/build-mobile-ios-simulator.sh" >/dev/null

actual_version=$("$target_prefix/bin/ocamlopt.opt" -version)
[[ $actual_version == "$ocaml_version" ]] || {
  echo "error: iOS compiler version is $actual_version, expected $ocaml_version" >&2
  exit 1
}

[[ -x $app ]] || {
  echo "error: iOS application was not built: $app" >&2
  exit 1
}

echo "Verified iOS uses official OCaml $ocaml_version without opam"
