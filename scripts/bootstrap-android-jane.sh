#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap-android-jane.sh [options] [package ...]

Build Jane Street OCaml packages for the opam-cross-android target toolchain and
install them into the switch's android-sysroot findlib tree.

Options:
  --switch NAME        Opam switch to use. Default: repository-local switch
  --workspace PATH     Dune workspace to use. Default: dune-workspace.basement-flags
  --jobs N             Dune build jobs. Default: 1
  --clean              Run dune clean before each package build
  --continue-from PKG  Skip packages before PKG in the selected package list
  --dry-run            Print the package plan without building
  --skip-host-tools    Do not link host PPX/compiler packages into android-sysroot
  -h, --help           Show this help

If no packages are provided, a dependency-ordered package list for the Android
native counter example is used.
EOF
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
switch_name=${OCAML_DEMO_ANDROID_OPAM_SWITCH:-${OCAML_DEMO_OPAM_SWITCH:-$repo_root}}
workspace=${OCAML_DEMO_ANDROID_WORKSPACE:-dune-workspace.basement-flags}
dune_jobs=${OCAML_DEMO_ANDROID_DUNE_JOBS:-1}
clean=false
dry_run=false
link_host_tools=true
continue_from=
packages=()

while (($# > 0)); do
  case "$1" in
    --switch)
      (($# >= 2)) || { echo "--switch requires a value" >&2; exit 2; }
      switch_name=$2
      shift 2
      ;;
    --workspace)
      (($# >= 2)) || { echo "--workspace requires a value" >&2; exit 2; }
      workspace=$2
      shift 2
      ;;
    --jobs)
      (($# >= 2)) || { echo "--jobs requires a value" >&2; exit 2; }
      dune_jobs=$2
      shift 2
      ;;
    --clean)
      clean=true
      shift
      ;;
    --continue-from)
      (($# >= 2)) || { echo "--continue-from requires a value" >&2; exit 2; }
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

if [[ $workspace != /* ]]; then
  workspace=$repo_root/$workspace
fi

switch_prefix=$(opam var --switch="$switch_name" prefix)
switch_lib=$(opam var --switch="$switch_name" lib)
sources_dir=$switch_prefix/.opam-switch/sources
sysroot=$switch_prefix/android-sysroot
sysroot_lib=$sysroot/lib

default_packages=(
  basement
  sexp_type
  sexplib0
  base_internalhash_types
  ocaml_intrinsics_kernel
  nonempty_list_type
  capsule0
  ppx_derivers
  stdlib-shims
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
  ppx_portable
  ppx_module_timer
  capitalization
  ppx_let
  ppx_fuelproof
  ppx_string
  ppx_log
  ppx_string_conv
  bin_prot
  unique
  parsexp
  num
  sexplib
  univ_map
  ppx_typed_fields
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
  record_builder
  core_unix_time_stamp_counter
  async_kernel
  flexible_sexp
  pipe_with_writer_error
  protocol_version_header
  core_extended_immediate_kernel
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
  selected=()
  found=false
  for package in "${packages[@]}"; do
    if [[ $package == "$continue_from" ]]; then
      found=true
    fi
    if [[ $found == true ]]; then
      selected+=("$package")
    fi
  done
  [[ $found == true ]] || { echo "--continue-from package is not in the selected package list: $continue_from" >&2; exit 2; }
  packages=("${selected[@]}")
fi

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

validate_environment() {
  require_command opam

  [[ -f $workspace ]] || { echo "Dune workspace does not exist: $workspace" >&2; exit 1; }
  [[ -d $sources_dir ]] || {
    echo "Opam source directory does not exist: $sources_dir" >&2
    echo "Install host dependencies before running this script." >&2
    exit 1
  }

  mkdir -p "$sysroot_lib"
  opam exec --switch="$switch_name" -- dune --version >/dev/null
  opam exec --switch="$switch_name" -- ocamlfind printconf >/dev/null
  opam exec --switch="$switch_name" -- ocamlfind -toolchain android printconf >/dev/null
  ensure_pic_runtime_aliases
}

ensure_pic_runtime_aliases() {
  local ocaml_dir=$sysroot_lib/ocaml
  local runtime

  for runtime in libasmrun libcamlrun; do
    if [[ -f $ocaml_dir/$runtime.a && ! -f $ocaml_dir/${runtime}_pic.a ]]; then
      cp "$ocaml_dir/$runtime.a" "$ocaml_dir/${runtime}_pic.a"
    fi
  done
}

find_source_dir() {
  local package=$1
  local source
  source=$(find "$sources_dir" -maxdepth 1 -type d -name "$package.*" | sort | tail -n 1)
  [[ -n $source ]] || { echo "No opam source directory found for $package under $sources_dir" >&2; exit 1; }
  printf '%s\n' "$source"
}

normalize_nested_sysroot() {
  local nested=$sysroot/android-sysroot

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

copy_if_exists() {
  local source=$1
  local target_dir=$2
  [[ -e $source ]] || return 0
  cp -L "$source" "$target_dir/"
}

source_workspace() {
  local source=$1
  local target=$source/dune-workspace.android
  cp "$workspace" "$target"
  printf '%s\n' dune-workspace.android
}

build_ppxlib() {
  local source=$1
  local source_workspace_file
  echo "==> ppxlib (target build with host-generated sources)"
  (
    cd "$source"
    if [[ ! -f src/ast_pattern_generated.ml || ! -f src/ast_builder_generated.ml ]]; then
      opam exec --switch="$switch_name" -- \
        dune build --root "$source" -j "$dune_jobs" src/ast_pattern_generated.ml src/ast_builder_generated.ml --display short
      cp _build/default/src/ast_pattern_generated.ml src/ast_pattern_generated.ml
      cp _build/default/src/ast_builder_generated.ml src/ast_builder_generated.ml
    fi
    if grep -q "gen/gen_ast_pattern.exe" src/dune; then
      perl -0pi -e 's/\n\(rule\n \(targets ast_pattern_generated\.ml\)\n \(deps gen\/gen_ast_pattern\.exe\)\n \(action\n  \(run \.\/gen\/gen_ast_pattern\.exe %\{lib:ppxlib\.ast:ast\.ml\}\)\)\)\n\n\(rule\n \(targets ast_builder_generated\.ml\)\n \(deps gen\/gen_ast_builder\.exe\)\n \(action\n  \(run \.\/gen\/gen_ast_builder\.exe %\{lib:ppxlib\.ast:ast\.ml\}\)\)\)\n/\n/s' src/dune
    fi
    source_workspace_file=$(source_workspace "$source")
    opam exec --switch="$switch_name" -- \
      dune build --workspace "$source_workspace_file" -j "$dune_jobs" -p ppxlib -x android @install --display short
  )

  rm -rf "$sysroot_lib/ppxlib" "$sysroot/android-sysroot"
  (
    cd "$source"
    source_workspace_file=$(source_workspace "$source")
    opam exec --switch="$switch_name" -- \
      dune install --workspace "$source_workspace_file" -j "$dune_jobs" -p ppxlib -x android --prefix "$sysroot" --display quiet || true
  )
  normalize_nested_sysroot

  opam exec --switch="$switch_name" -- ocamlfind -toolchain android query \
    ppxlib ppxlib.metaquot_lifters ppxlib.print_diff ppxlib.stdppx \
    ppxlib.ast ppxlib.astlib ppxlib.traverse_builtins >/dev/null
  if [[ -L $sysroot_lib/ppxlib ]]; then
    echo "ppxlib still resolves to a host symlink after target build" >&2
    exit 1
  fi
}

build_virtual_dom_ui_effect() {
  local source=$1
  local source_workspace_file
  local build_dir=$source/_build/default.android/ui_effect/src
  local byte_dir=$build_dir/.ui_effect.objs/byte
  local native_dir=$build_dir/.ui_effect.objs/native
  local package_dir=$sysroot_lib/virtual_dom
  local install_dir=$package_dir/ui_effect

  echo "==> virtual_dom.ui_effect"
  (
    cd "$source"
    source_workspace_file=$(source_workspace "$source")
    opam exec --switch="$switch_name" -- \
      dune build --root "$source" --workspace "$source_workspace_file" -j "$dune_jobs" -x android ui_effect/src/ui_effect.cma ui_effect/src/ui_effect.cmxa --display short
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

  for artifact in ui_effect.cmx ui_effect__.cmx ui_effect__Ui_effect_intf.cmx; do
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

build_uutf() {
  local source=$1
  local build_dir=$source/_build/android-manual
  local install_dir=$sysroot_lib/uutf

  echo "==> uutf (manual target build)"
  rm -rf "$build_dir" "$install_dir"
  mkdir -p "$build_dir" "$install_dir"

  opam exec --switch="$switch_name" -- \
    ocamlfind -toolchain android ocamlc -g -bin-annot -c \
      -o "$build_dir/uutf.cmi" "$source/src/uutf.mli"
  opam exec --switch="$switch_name" -- \
    ocamlfind -toolchain android ocamlc -g -bin-annot -I "$build_dir" -c \
      -o "$build_dir/uutf.cmo" "$source/src/uutf.ml"
  opam exec --switch="$switch_name" -- \
    ocamlfind -toolchain android ocamlc -a -o "$build_dir/uutf.cma" \
      "$build_dir/uutf.cmo"
  opam exec --switch="$switch_name" -- \
    ocamlfind -toolchain android ocamlopt -g -I "$build_dir" -c \
      -o "$build_dir/uutf.cmx" "$source/src/uutf.ml"
  opam exec --switch="$switch_name" -- \
    ocamlfind -toolchain android ocamlopt -a -o "$build_dir/uutf.cmxa" \
      "$build_dir/uutf.cmx"

  cp "$source/src/uutf.ml" "$source/src/uutf.mli" "$install_dir/"
  cp "$build_dir"/uutf.{a,cma,cmi,cmt,cmti,cmx,cmxa,o} "$install_dir/"
  cp "$source/pkg/META" "$install_dir/META"
}

build_core_unix_time_stamp_counter() {
  local source=$1
  local build_dir=$source/_build/default.android/time_stamp_counter/src
  local byte_dir=$build_dir/.time_stamp_counter.objs/byte
  local native_dir=$build_dir/.time_stamp_counter.objs/native
  local package_dir=$sysroot_lib/core_unix
  local install_dir=$package_dir/time_stamp_counter
  local source_workspace_file

  echo "==> core_unix.time_stamp_counter"
  (
    cd "$source"
    source_workspace_file=$(source_workspace "$source")
    opam exec --switch="$switch_name" -- \
      dune build --root "$source" --workspace "$source_workspace_file" -j "$dune_jobs" -x android \
        time_stamp_counter/src/time_stamp_counter.cma \
        time_stamp_counter/src/time_stamp_counter.cmxa \
        --display short
  )

  rm -rf "$install_dir"
  mkdir -p "$install_dir"

  for artifact in \
    time_stamp_counter.a time_stamp_counter.cma time_stamp_counter.cmxa \
    time_stamp_counter.ml time_stamp_counter.mli; do
    copy_if_exists "$build_dir/$artifact" "$install_dir"
  done

  for artifact in \
    time_stamp_counter.cmi time_stamp_counter.cmt time_stamp_counter.cmti \
    time_stamp_counter__.cmi time_stamp_counter__.cmt \
    time_stamp_counter__Import.cmi time_stamp_counter__Import.cmt; do
    copy_if_exists "$byte_dir/$artifact" "$install_dir"
  done

  for artifact in \
    time_stamp_counter.cmx time_stamp_counter__.cmx time_stamp_counter__Import.cmx; do
    copy_if_exists "$native_dir/$artifact" "$install_dir"
  done

  copy_if_exists "$source/time_stamp_counter/src/import.ml" "$install_dir"
  copy_if_exists "$build_dir/time_stamp_counter__.ml-gen" "$install_dir"
  if [[ -f $install_dir/time_stamp_counter__.ml-gen ]]; then
    mv "$install_dir/time_stamp_counter__.ml-gen" "$install_dir/time_stamp_counter__.ml"
  fi

  cat >"$package_dir/META" <<'EOF'
description = "Subset of core_unix needed by Async_kernel on Android"
version = "v0.18~preview.130.100+614"
package "time_stamp_counter" (
  directory = "time_stamp_counter"
  requires = "core"
  archive(byte) = "time_stamp_counter.cma"
  archive(native) = "time_stamp_counter.cmxa"
  plugin(byte) = "time_stamp_counter.cma"
)
EOF
}

build_core_extended_immediate_kernel() {
  local source=$1
  local build_dir=$source/_build/default.android/immediate/kernel/src
  local byte_dir=$build_dir/.immediate_kernel.objs/byte
  local native_dir=$build_dir/.immediate_kernel.objs/native
  local package_dir=$sysroot_lib/core_extended
  local install_dir=$package_dir/immediate_kernel
  local source_workspace_file

  echo "==> core_extended.immediate_kernel"
  (
    cd "$source"
    source_workspace_file=$(source_workspace "$source")
    opam exec --switch="$switch_name" -- \
      dune build --root "$source" --workspace "$source_workspace_file" -j "$dune_jobs" -x android \
        immediate/kernel/src/immediate_kernel.cma \
        immediate/kernel/src/immediate_kernel.cmxa \
        --display short
  )

  rm -rf "$install_dir"
  mkdir -p "$install_dir"

  for artifact in \
    immediate_kernel.a immediate_kernel.cma immediate_kernel.cmxa \
    immediate_kernel.ml immediate_kernel.mli immediate_kernel_intf.ml; do
    copy_if_exists "$build_dir/$artifact" "$install_dir"
  done

  for artifact in \
    immediate_kernel.cmi immediate_kernel.cmt immediate_kernel.cmti \
    immediate_kernel__.cmi immediate_kernel__.cmt \
    immediate_kernel__Immediate_kernel_intf.cmi \
    immediate_kernel__Immediate_kernel_intf.cmt; do
    copy_if_exists "$byte_dir/$artifact" "$install_dir"
  done

  for artifact in \
    immediate_kernel.cmx immediate_kernel__.cmx \
    immediate_kernel__Immediate_kernel_intf.cmx; do
    copy_if_exists "$native_dir/$artifact" "$install_dir"
  done

  copy_if_exists "$build_dir/immediate_kernel__.ml-gen" "$install_dir"
  if [[ -f $install_dir/immediate_kernel__.ml-gen ]]; then
    mv "$install_dir/immediate_kernel__.ml-gen" "$install_dir/immediate_kernel__.ml"
  fi

  cat >"$package_dir/META" <<'EOF'
description = "Subset of core_extended needed by Async_rpc_kernel on Android"
version = "v0.18~preview.130.100+614"
package "immediate_kernel" (
  directory = "immediate_kernel"
  requires = "bin_prot.shape core"
  archive(byte) = "immediate_kernel.cma"
  archive(native) = "immediate_kernel.cmxa"
  plugin(byte) = "immediate_kernel.cma"
)
EOF
}

target_c_compiler() {
  opam exec --switch="$switch_name" -- \
    ocamlfind -toolchain android ocamlc -config | sed -n 's/^c_compiler: //p'
}

target_llvm_tool() {
  local compiler=$1
  local tool=$2
  local tool_path
  tool_path=$(dirname "$compiler")/$tool

  if [[ -x $tool_path ]]; then
    printf '%s\n' "$tool_path"
  else
    command -v "$tool" || {
      echo "Missing Android target tool: $tool" >&2
      exit 1
    }
  fi
}

build_gmp() {
  local version=6.3.0
  local archive=$sysroot/src/gmp-$version.tar.xz
  local source=$sysroot/src/gmp-$version
  local compiler
  local ar
  local ranlib

  if [[ $clean == false && -f $sysroot_lib/libgmp.a && -f $sysroot/include/gmp.h ]]; then
    echo "==> gmp (already installed)"
    return 0
  fi

  require_command curl
  require_command make
  require_command tar

  compiler=$(target_c_compiler)
  [[ -n $compiler && -x $compiler ]] || {
    echo "Android target C compiler is not executable: $compiler" >&2
    exit 1
  }
  ar=$(target_llvm_tool "$compiler" llvm-ar)
  ranlib=$(target_llvm_tool "$compiler" llvm-ranlib)

  echo "==> gmp $version"
  mkdir -p "$sysroot/src"
  if [[ ! -f $archive ]]; then
    curl --fail --location --output "$archive" \
      "https://ftp.gnu.org/gnu/gmp/gmp-$version.tar.xz"
  fi

  rm -rf "$source"
  tar -C "$sysroot/src" -xf "$archive"

  (
    cd "$source"
    CC="$compiler" AR="$ar" RANLIB="$ranlib" \
      CFLAGS="-O2 -fPIC" \
      ./configure \
        --host=aarch64-linux-android \
        --prefix="$sysroot" \
        --disable-shared \
        --enable-static \
        --disable-assembly
    make -j "$dune_jobs"
    make install
  )

  [[ -f $sysroot_lib/libgmp.a && -f $sysroot/include/gmp.h ]] || {
    echo "GMP did not install into the Android sysroot" >&2
    exit 1
  }
}

build_zarith() {
  local source=$1
  local compiler

  build_gmp
  compiler=$(target_c_compiler)

  echo "==> zarith"
  rm -rf "$sysroot_lib/zarith"

  (
    cd "$source"
    make clean >/dev/null 2>&1 || true
    PATH="$switch_prefix/bin:$PATH" \
      PKG_CONFIG_LIBDIR="$sysroot_lib/pkgconfig" \
      CC="$compiler" \
      CPPFLAGS="-I$sysroot/include" \
      LDFLAGS="-L$sysroot_lib" \
      ./configure \
        -installdir "$sysroot_lib" \
        -ocamllibdir "$sysroot_lib/ocaml" \
        -gmp
    opam exec --switch="$switch_name" -- make -j "$dune_jobs" \
      HASDYNLINK=no \
      OCAMLC="ocamlfind -toolchain android ocamlc" \
      OCAMLOPT="ocamlfind -toolchain android ocamlopt" \
      OCAMLMKLIB="ocamlfind -toolchain android ocamlmklib" \
      OCAMLDEP="ocamlfind -toolchain android ocamldep"
    opam exec --switch="$switch_name" -- make install \
      HASDYNLINK=no \
      OCAMLFIND="ocamlfind -toolchain android" \
      INSTALLDIR="$sysroot_lib"
  )

  opam exec --switch="$switch_name" -- ocamlfind -toolchain android query zarith >/dev/null
  if [[ -L $sysroot_lib/zarith ]]; then
    echo "zarith still resolves to a host symlink after target build" >&2
    exit 1
  fi
}

patch_time_now_source() {
  local source=$1
  local file=$source/src/time_now_stubs.c

  if ! grep -q "__ANDROID__" "$file"; then
    perl -0pi -e 's/#if defined\(JSC_TIMESPEC\)\n/#if defined(__ANDROID__)\n\nCAMLprim value time_now_nanoseconds_since_unix_epoch_or_zero() {\n  struct timespec ts;\n\n  if (clock_gettime(CLOCK_REALTIME, \&ts) != 0)\n    return caml_alloc_int63(0);\n  else\n    return caml_alloc_int63(NANOS_PER_SECOND * (uint64_t)ts.tv_sec +\n                            (uint64_t)ts.tv_nsec);\n}\n\n#elif defined(JSC_TIMESPEC)\n/s' "$file"
  fi
}

build_and_install_package() {
  local package=$1
  local source
  local source_workspace_file

  if is_host_tool_package "$package"; then
    link_host_package "$switch_lib/$package"
    opam exec --switch="$switch_name" -- ocamlfind -toolchain android query "$package" >/dev/null
    echo "==> $package (host tool link)"
    return 0
  fi

  if [[ $package == core_unix_time_stamp_counter ]]; then
    source=$(find_source_dir core_unix)
    build_core_unix_time_stamp_counter "$source"
    opam exec --switch="$switch_name" -- ocamlfind -toolchain android query core_unix.time_stamp_counter >/dev/null
    return 0
  fi

  if [[ $package == core_extended_immediate_kernel ]]; then
    source=$(find_source_dir core_extended)
    build_core_extended_immediate_kernel "$source"
    opam exec --switch="$switch_name" -- ocamlfind -toolchain android query core_extended.immediate_kernel >/dev/null
    return 0
  fi

  source=$(find_source_dir "$package")

  if [[ $package == ppxlib ]]; then
    build_ppxlib "$source"
    return 0
  fi

  if [[ $package == virtual_dom ]]; then
    build_virtual_dom_ui_effect "$source"
    opam exec --switch="$switch_name" -- ocamlfind -toolchain android query virtual_dom.ui_effect >/dev/null
    return 0
  fi

  if [[ $package == uutf ]]; then
    build_uutf "$source"
    opam exec --switch="$switch_name" -- ocamlfind -toolchain android query uutf >/dev/null
    return 0
  fi

  if [[ $package == zarith ]]; then
    build_zarith "$source"
    return 0
  fi

  echo "==> $package"
  if [[ $package == time_now ]]; then
    patch_time_now_source "$source"
  fi

  if [[ -L $sysroot_lib/$package ]]; then
    rm -f "$sysroot_lib/$package"
  fi

  (
    cd "$source"
    if [[ $clean == true ]]; then
      opam exec --switch="$switch_name" -- dune clean
    fi
    source_workspace_file=$(source_workspace "$source")
    opam exec --switch="$switch_name" -- \
      dune build --workspace "$source_workspace_file" -j "$dune_jobs" -p "$package" -x android @install --display short
    opam exec --switch="$switch_name" -- \
      dune install --workspace "$source_workspace_file" -j "$dune_jobs" -p "$package" -x android --prefix "$sysroot" --display quiet || true
  )

  normalize_nested_sysroot
  if ! opam exec --switch="$switch_name" -- ocamlfind -toolchain android query "$package" >/dev/null; then
    echo "Package did not install into the Android target findlib tree: $package" >&2
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
echo "jobs:      $dune_jobs"
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
