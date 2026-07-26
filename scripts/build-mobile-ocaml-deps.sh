#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 TARGET_PREFIX BUILD_DIRECTORY" >&2
  exit 2
fi

target_prefix=$(cd "$1" && pwd)
mkdir -p "$2"
build_dir=$(cd "$2" && pwd)
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_root="$repo_root/_build/mobile-dependency-sources"
datascript_source="$source_root/datascript-ocaml"
persistent_set_source="$source_root/persistent-sorted-set-ocaml"
datascript_revision=3e9bee227686ba8608fc3fb027c4ebe30961360f
persistent_set_revision=f95398e77a1a003f65ecf201c4aede961e52e929
ocamlopt="$target_prefix/bin/ocamlopt.opt"
ocamldep="$target_prefix/bin/ocamldep.opt"
source_dir="$build_dir/mobile-ocaml-deps-source"
object_dir="$build_dir/mobile-ocaml-deps"

clone_revision() {
  local url=$1
  local revision=$2
  local destination=$3

  if [[ ! -d $destination/.git ]]; then
    git clone "$url" "$destination"
  fi
  git -C "$destination" fetch origin "$revision"
  git -C "$destination" checkout --detach "$revision"
}

clone_revision \
  https://github.com/logseq/datascript-ocaml.git \
  "$datascript_revision" \
  "$datascript_source"
clone_revision \
  https://github.com/logseq/persistent-sorted-set-ocaml.git \
  "$persistent_set_revision" \
  "$persistent_set_source"

mkdir -p "$source_dir" "$object_dir"

ln -sf \
  "$persistent_set_source/lib/persistent_sorted_set.mli" \
  "$source_dir/persistent_sorted_set.mli"
ln -sf \
  "$persistent_set_source/lib/persistent_sorted_set.ml" \
  "$source_dir/persistent_sorted_set.ml"
ln -sf \
  "$persistent_set_source/lib/platform_weak_slot.mli" \
  "$source_dir/platform_weak_slot.mli"
ln -sf \
  "$persistent_set_source/lib/platform/native/platform_weak_slot.ml" \
  "$source_dir/platform_weak_slot.ml"
ln -sf \
  "$datascript_source/type/datascript_types.ml" \
  "$source_dir/datascript_types.ml"
ln -sf \
  "$datascript_source/impl/platform.mli" \
  "$source_dir/platform.mli"
ln -sf \
  "$datascript_source/impl/platform/native/platform.ml" \
  "$source_dir/platform.ml"

for source in "$datascript_source"/impl/*.ml "$datascript_source"/impl/*.mli; do
  ln -sf "$source" "$source_dir/$(basename "$source")"
done

cd "$source_dir"
ordered_sources=$("$ocamldep" -sort ./*.mli ./*.ml)

cd "$object_dir"
for source in $ordered_sources; do
  source_path="$source_dir/${source#./}"
  module_name=$(basename "$source")
  case "$source" in
    *.mli)
      "$ocamlopt" -I "$object_dir" -c "$source_path" \
        -o "${module_name%.mli}.cmi"
      ;;
    *.ml)
      "$ocamlopt" -I "$object_dir" -c "$source_path" \
        -o "${module_name%.ml}.cmx"
      ;;
  esac
done

cmx_list=$("$ocamldep" -sort "$source_dir"/*.ml)
: >"$object_dir/link-objects.txt"
for source in $cmx_list; do
  printf '%s\n' "$object_dir/$(basename "${source%.ml}.cmx")" \
    >>"$object_dir/link-objects.txt"
done

printf '%s\n' "$datascript_source/sqlite/datascript_sqlite_stubs.c" \
  >"$object_dir/sqlite-stub-source.txt"
