#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap-ios-jane.sh [options] [package ...]

Build Jane Street OCaml packages for the opam-cross-ios target toolchain and
install them into the switch's ios-sysroot findlib tree.

Options:
  --switch NAME        Opam switch to use. Default: simulator-5.4.1
  --workspace PATH     Dune workspace to use. Default: dune-workspace.basement-flags
  --clean              Run dune clean before each package build
  --continue-from PKG  Skip packages before PKG in the selected package list
  --dry-run            Print the package plan without building
  --skip-host-tools    Do not link host PPX/compiler packages into ios-sysroot
  -h, --help           Show this help

If no packages are provided, a dependency-ordered package list for the current
ocaml-demo iOS example is used.

Run this after installing the host package dependencies with:
  DUNE_WORKSPACE=$PWD/dune-workspace.basement-flags opam install . --deps-only --with-test
EOF
}

switch_name=${OCAML_DEMO_APPLE_IOS_SWITCH:-${OCAML_DEMO_IOS_SWITCH:-simulator-5.4.1}}
workspace=${OCAML_DEMO_APPLE_IOS_WORKSPACE:-${OCAML_DEMO_IOS_WORKSPACE:-dune-workspace.basement-flags}}
clean=false
dry_run=false
link_host_tools=true
continue_from=
packages=()

while (($# > 0)); do
  case "$1" in
    --switch)
      if (($# < 2)); then
        echo "--switch requires a value" >&2
        exit 2
      fi
      switch_name=$2
      shift 2
      ;;
    --workspace)
      if (($# < 2)); then
        echo "--workspace requires a value" >&2
        exit 2
      fi
      workspace=$2
      shift 2
      ;;
    --clean)
      clean=true
      shift
      ;;
    --continue-from)
      if (($# < 2)); then
        echo "--continue-from requires a value" >&2
        exit 2
      fi
      continue_from=$2
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --skip-host-tools)
      link_host_tools=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      packages+=("$@")
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      packages+=("$1")
      shift
      ;;
  esac
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $workspace != /* ]]; then
  workspace=$repo_root/$workspace
fi

switch_prefix=$(opam var --switch="$switch_name" prefix)
switch_lib=$(opam var --switch="$switch_name" lib)
sources_dir=$switch_prefix/.opam-switch/sources
sysroot=$switch_prefix/ios-sysroot
sysroot_lib=$sysroot/lib
ios_target=${IOS_TARGET:-arm64-apple-ios17.0}
ios_sdkroot=${IOS_SDKROOT:-}

default_packages=(
  basement
  sexp_type
  sexplib0
  base_internalhash_types
  ocaml_intrinsics_kernel
  nonempty_list_type
  capsule0
  ppx_derivers
  ppxlib
  ppx_template
  ppx_shorthand
  ppx_compare
  ppx_hash
  ppx_sexp_conv
  ppx_enumerate
  base
  fieldslib
  variantslib
  capsule
  jane-street-headers
  time_now
  ppx_here
  ppx_assert
  ppx_inline_test
  ppx_bench
  ppx_sexp_message
  splittable_random
  base_quickcheck
  portable
  typerep
  ppx_stable_witness
  stdio
  ppx_expect
  ppx_module_timer
  capitalization
  ppx_let
  ppx_string
  ppx_string_conv
  bin_prot
  unique
  parsexp
  num
  sexplib
  univ_map
  ppx_diff
  int_repr
  uopt
  base_bigstring
  string_dict
  uutf
  textutils_kernel
  janestreet_lru_cache
  incremental
  incr_select
  stored_reversed
  re
  sexp_pretty
  expect_test_helpers_base
  spawn
  core_unix
  record_builder
  core_extended
  async_kernel
  flexible_sexp
  pipe_with_writer_error
  protocol_version_header
  async_rpc_kernel
  streamable
  legacy_diffable
  abstract_algebra
  ppx_pattern_bind
  zarith
  zarith_stubs_js
  bignum
  incr_map
  virtual_dom
  ocaml_demo_concrete
  ocaml_demo
)

if ((${#packages[@]} == 0)); then
  packages=("${default_packages[@]}")
fi

if [[ -n $continue_from ]]; then
  skipped=()
  found=false
  for package in "${packages[@]}"; do
    if [[ $package == "$continue_from" ]]; then
      found=true
    fi
    if [[ $found == true ]]; then
      skipped+=("$package")
    fi
  done
  if [[ $found != true ]]; then
    echo "--continue-from package is not in the selected package list: $continue_from" >&2
    exit 2
  fi
  packages=("${skipped[@]}")
fi

require_command() {
  local command=$1
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
}

validate_environment() {
  require_command opam
  require_command xcrun

  if [[ ! -f $workspace ]]; then
    echo "Dune workspace does not exist: $workspace" >&2
    exit 1
  fi

  if [[ ! -d $sources_dir ]]; then
    echo "Opam source directory does not exist: $sources_dir" >&2
    echo "Install host dependencies before running this script." >&2
    exit 1
  fi

  mkdir -p "$sysroot_lib"
  opam exec --switch="$switch_name" -- dune --version >/dev/null
  opam exec --switch="$switch_name" -- ocamlfind printconf >/dev/null
  opam exec --switch="$switch_name" -- ocamlfind -toolchain ios printconf >/dev/null
}

find_source_dir() {
  local package=$1
  local source
  if [[ -f $repo_root/$package.opam ]]; then
    printf '%s\n' "$repo_root"
    return 0
  fi
  source=$(
    find "$sources_dir" -maxdepth 1 -type d \( -name "$package" -o -name "$package.*" \) \
      | sort \
      | tail -n 1
  )
  if [[ -z $source ]]; then
    echo "No opam source directory found for $package under $sources_dir" >&2
    exit 1
  fi
  printf '%s\n' "$source"
}

normalize_nested_sysroot() {
  local nested=$sysroot/ios-sysroot

  if [[ -d $nested/lib ]]; then
    mkdir -p "$sysroot_lib"
    local item
    for item in "$nested"/lib/*; do
      [[ -e $item ]] || continue
      rm -rf "$sysroot_lib/$(basename "$item")"
    done
    cp -a "$nested"/lib/* "$sysroot_lib/"
  fi

  if [[ -d $nested/doc ]]; then
    mkdir -p "$sysroot/doc"
    local item
    for item in "$nested"/doc/*; do
      [[ -e $item ]] || continue
      rm -rf "$sysroot/doc/$(basename "$item")"
    done
    cp -a "$nested"/doc/* "$sysroot/doc/"
  fi

  rm -rf "$nested"
}

link_host_package() {
  local path=$1
  [[ -e $path ]] || return 0
  local name
  name=$(basename "$path")

  if [[ -e $sysroot_lib/$name && ! -L $sysroot_lib/$name ]]; then
    return 0
  fi

  rm -f "$sysroot_lib/$name"
  ln -s "$path" "$sysroot_lib/$name"
}

link_host_tool_packages() {
  mkdir -p "$sysroot_lib"

  local path
  for path in "$switch_lib"/ppx*; do
    [[ $(basename "$path") == ppxlib ]] && continue
    link_host_package "$path"
  done

  link_host_package "$switch_lib/ocaml-compiler-libs"
  link_host_package "$switch_lib/ocaml-syntax-shims"
  link_host_package "$switch_lib/csexp"
  link_host_package "$switch_lib/dune-configurator"
  link_host_package "$switch_lib/jst-config"
  link_host_package "$switch_lib/astring"
  link_host_package "$switch_lib/camlp-streams"
  link_host_package "$switch_lib/odoc-parser"
  link_host_package "$switch_lib/gen_js_api"
  link_host_package "$switch_lib/js_of_ocaml"
  link_host_package "$switch_lib/js_of_ocaml-compiler"
  link_host_package "$switch_lib/js_of_ocaml-ppx"
}

is_host_tool_package() {
  case "$1" in
    astring|camlp-streams|csexp|dune-configurator|gen_js_api|js_of_ocaml|js_of_ocaml-compiler|js_of_ocaml-ppx|jst-config|odoc-parser)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

build_uutf() {
  local source=$1
  local build_dir=$source/_build/ios-manual
  local target_ocamlc=$sysroot/bin/ocamlc
  local target_ocamlopt=$sysroot/bin/ocamlopt
  local install_dir=$sysroot_lib/uutf

  echo "==> uutf (manual target build)"
  rm -rf "$build_dir" "$install_dir"
  mkdir -p "$build_dir" "$install_dir"

  cp "$source/src/uutf.ml" "$source/src/uutf.mli" "$build_dir/"
  (
    cd "$build_dir"
    "$target_ocamlc" -g -bin-annot -c uutf.mli
    "$target_ocamlc" -g -bin-annot -c uutf.ml
    "$target_ocamlc" -a -o uutf.cma uutf.cmo
    "$target_ocamlopt" -g -c uutf.ml
    "$target_ocamlopt" -a -o uutf.cmxa uutf.cmx
  )

  cp "$source/pkg/META" "$install_dir/META"
  cp "$source/opam" "$install_dir/opam"
  cp "$build_dir"/uutf.{a,cma,cmi,cmt,cmti,cmx,cmxa,ml,mli,o} "$install_dir/"
}

build_zarith() {
  echo "==> zarith (zarith-ios)"
  opam install --switch="$switch_name" --yes zarith-ios
}

target_clang() {
  xcrun --sdk iphoneos -f clang
}

target_sdkroot() {
  if [[ -n $ios_sdkroot ]]; then
    printf '%s\n' "$ios_sdkroot"
  else
    xcrun --sdk iphoneos --show-sdk-path
  fi
}

copy_if_exists() {
  local source=$1
  local target_dir=$2
  [[ -e $source ]] || return 0
  cp -L "$source" "$target_dir/"
}

build_ppxlib() {
  local source=$1

  echo "==> ppxlib (target build with host-generated sources)"
  (
    cd "$source"
    DUNE_WORKSPACE="$workspace" opam exec --switch="$switch_name" -- \
      dune build src/ast_pattern_generated.ml src/ast_builder_generated.ml --display short
    rm -f src/ast_pattern_generated.ml src/ast_builder_generated.ml
    cp _build/default/src/ast_pattern_generated.ml src/ast_pattern_generated.ml
    cp _build/default/src/ast_builder_generated.ml src/ast_builder_generated.ml
    DUNE_WORKSPACE="$workspace" opam exec --switch="$switch_name" -- \
      dune build -p ppxlib -x ios @install --display short
  )

  rm -rf "$sysroot_lib/ppxlib" "$sysroot/ios-sysroot"
  (
    cd "$source"
    DUNE_WORKSPACE="$workspace" opam exec --switch="$switch_name" -- \
      dune install -p ppxlib -x ios --prefix "$switch_prefix" --display quiet || true
  )
  normalize_nested_sysroot

  opam exec --switch="$switch_name" -- ocamlfind -toolchain ios query \
    ppxlib ppxlib.metaquot_lifters ppxlib.print_diff ppxlib.stdppx \
    ppxlib.ast ppxlib.astlib ppxlib.traverse_builtins >/dev/null
  if [[ -L $sysroot_lib/ppxlib ]]; then
    echo "ppxlib still resolves to a host symlink after target build" >&2
    exit 1
  fi
}

replace_time_now_stubs() {
  local source=$1
  local install_dir=$sysroot_lib/time_now
  local sdkroot
  local clang
  local temp_dir

  if [[ ! -d $install_dir ]]; then
    return 0
  fi

  echo "==> time_now (iOS C stubs)"
  sdkroot=$(target_sdkroot)
  clang=$(target_clang)
  temp_dir=$(mktemp -d)

  "$clang" -target "$ios_target" -isysroot "$sdkroot" -miphoneos-version-min=17.0 \
    -std=c11 -fPIC -O2 -fno-strict-aliasing -fwrapv -D_FILE_OFFSET_BITS=64 \
    -I"$source/_build/default.ios/src" \
    -I"$sysroot_lib/ocaml" \
    -I"$sysroot_lib/jane-street-headers" \
    -c "$source/src/time_now_stubs.c" -o "$temp_dir/time_now_stubs.o"
  ar rcs "$temp_dir/libtime_now_stubs.a" "$temp_dir/time_now_stubs.o"
  cp "$temp_dir/libtime_now_stubs.a" "$install_dir/libtime_now_stubs.a"
  rm -rf "$temp_dir"
}

build_virtual_dom_ui_effect() {
  local source=$1
  local build_dir=$source/_build/default.ios/ui_effect/src
  local byte_dir=$build_dir/.ui_effect.objs/byte
  local native_dir=$build_dir/.ui_effect.objs/native
  local package_dir=$sysroot_lib/virtual_dom
  local install_dir=$package_dir/ui_effect

  echo "==> virtual_dom.ui_effect"
  (
    cd "$source"
    DUNE_WORKSPACE="$workspace" opam exec --switch="$switch_name" -- \
      dune build -x ios ui_effect/src/ui_effect.cma ui_effect/src/ui_effect.cmxa --display short
  )

  rm -rf "$install_dir"
  mkdir -p "$install_dir"

  for artifact in ui_effect.a ui_effect.cma ui_effect.cmxa ui_effect.ml ui_effect.mli; do
    copy_if_exists "$build_dir/$artifact" "$install_dir"
  done

  for artifact in \
    ui_effect.cmi ui_effect.cmt ui_effect.cmti \
    ui_effect__.cmi ui_effect__.cmt \
    ui_effect__Ui_effect_intf.cmi ui_effect__Ui_effect_intf.cmt; do
    copy_if_exists "$byte_dir/$artifact" "$install_dir"
  done

  for artifact in \
    ui_effect.cmx ui_effect__.cmx ui_effect__Ui_effect_intf.cmx; do
    copy_if_exists "$native_dir/$artifact" "$install_dir"
  done

  copy_if_exists "$source/ui_effect/src/ui_effect_intf.ml" "$install_dir"
  copy_if_exists "$build_dir/ui_effect__.ml-gen" "$install_dir"
  if [[ -f $install_dir/ui_effect__.ml-gen ]]; then
    mv "$install_dir/ui_effect__.ml-gen" "$install_dir/ui_effect__.ml"
  fi

  cat >"$package_dir/META" <<'EOF'
description = "Subset of virtual_dom needed by native OCaml backends"
version = "v0.18~preview.130.100+614"
package "ui_effect" (
  directory = "ui_effect"
  requires = "base stdio"
  archive(byte) = "ui_effect.cma"
  archive(native) = "ui_effect.cmxa"
  plugin(byte) = "ui_effect.cma"
)
EOF
}

build_and_install_package() {
  local package=$1
  local source

  if is_host_tool_package "$package"; then
    link_host_package "$switch_lib/$package"
    opam exec --switch="$switch_name" -- ocamlfind -toolchain ios query "$package" >/dev/null
    echo "==> $package (host tool link)"
    return 0
  fi

  if [[ $package == zarith ]]; then
    build_zarith
    opam exec --switch="$switch_name" -- ocamlfind -toolchain ios query "$package" >/dev/null
    return 0
  fi

  source=$(find_source_dir "$package")

  if [[ $package == ppxlib ]]; then
    build_ppxlib "$source"
    return 0
  fi

  if [[ $package == virtual_dom ]]; then
    build_virtual_dom_ui_effect "$source"
    opam exec --switch="$switch_name" -- ocamlfind -toolchain ios query virtual_dom.ui_effect >/dev/null
    return 0
  fi

  if [[ $package == uutf ]]; then
    build_uutf "$source"
    opam exec --switch="$switch_name" -- ocamlfind -toolchain ios query "$package" >/dev/null
    return 0
  fi

  echo "==> $package"
  if [[ -L $sysroot_lib/$package ]]; then
    rm -f "$sysroot_lib/$package"
  fi
  rm -rf "$sysroot/ios-sysroot"

  (
    cd "$source"
    if [[ $clean == true ]]; then
      DUNE_WORKSPACE="$workspace" opam exec --switch="$switch_name" -- dune clean
    fi
    DUNE_WORKSPACE="$workspace" opam exec --switch="$switch_name" -- \
      dune build -p "$package" -x ios @install --display short
    DUNE_WORKSPACE="$workspace" opam exec --switch="$switch_name" -- \
      dune install -p "$package" -x ios --prefix "$switch_prefix" --display quiet || true
  )

  normalize_nested_sysroot
  if [[ $package == time_now ]]; then
    replace_time_now_stubs "$source"
  fi
  if ! opam exec --switch="$switch_name" -- ocamlfind -toolchain ios query "$package" >/dev/null; then
    echo "Package did not install into the iOS target findlib tree: $package" >&2
    exit 1
  fi
  if [[ -L $sysroot_lib/$package ]]; then
    echo "Package still resolves to a host symlink after target build: $package" >&2
    exit 1
  fi
}

validate_environment

echo "switch:    $switch_name"
echo "workspace: $workspace"
echo "sysroot:   $sysroot"
echo "packages:  ${packages[*]}"

if [[ $dry_run == true ]]; then
  exit 0
fi

if [[ $link_host_tools == true ]]; then
  echo "==> linking host PPX/compiler packages"
  link_host_tool_packages
fi

for package in "${packages[@]}"; do
  build_and_install_package "$package"
done

echo "Done."
