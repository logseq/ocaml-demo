#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
android_abi=${OCAML_DEMO_ANDROID_ABI:-arm64-v8a}
dune_target=${OCAML_DEMO_ANDROID_DUNE_TARGET:-android}
opam_switch=${OCAML_DEMO_ANDROID_OPAM_SWITCH:-${OCAML_DEMO_OPAM_SWITCH:-$repo_root}}
native_lib_name=libocaml_demo_android_counter.so
out_dir="$repo_root/android/_build/android/jniLibs/$android_abi"
artifact="$repo_root/_build/default.$dune_target/android/examples/android_counter_entry.so"

die() {
  echo "error: $*" >&2
  exit 1
}

require_file() {
  [[ -e "$1" ]] || die "$2"
}

require_file "$android_home" "ANDROID_HOME does not exist: $android_home"

if ! opam switch list --short | grep -qx "$opam_switch"; then
  cat >&2 <<EOF
error: missing opam switch '$opam_switch'

Create an Android OCaml cross switch first. The currently viable upstream path
is logseq/opam-cross-android with OCaml 5.2.1, for example a repo-local switch:

  $opam_switch

See docs/android-native-build.md for the bootstrap commands.
EOF
  exit 1
fi

if ! opam exec --switch="$opam_switch" -- ocamlfind -toolchain "$dune_target" printconf >/dev/null 2>&1; then
  die "opam switch '$opam_switch' does not expose ocamlfind toolchain '$dune_target'"
fi

opam exec --switch="$opam_switch" -- \
  dune build -x "$dune_target" android/examples/android_counter_entry.so --display short

require_file "$artifact" "expected Dune artifact was not produced: $artifact"

mkdir -p "$out_dir"
rm -f "$out_dir/$native_lib_name"
cp "$artifact" "$out_dir/$native_lib_name"

echo "Copied $artifact"
echo "  -> $out_dir/$native_lib_name"
