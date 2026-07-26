#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ocaml_version=${OCAML_DEMO_ANDROID_OCAML_VERSION:-5.5.0}
android_abi=${OCAML_DEMO_ANDROID_ABI:-arm64-v8a}
api_level=${OCAML_DEMO_ANDROID_API_LEVEL:-21}
android_home=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}

die() {
  echo "error: $*" >&2
  exit 1
}

case "$android_abi" in
  arm64-v8a)
    target_arch=aarch64
    ;;
  x86_64)
    target_arch=x86_64
    ;;
  *)
    die "unsupported Android ABI: $android_abi"
    ;;
esac

target="${target_arch}-linux-android${api_level}"
target_prefix="$repo_root/_build/android-toolchain/$target-$ocaml_version"
build_dir="$repo_root/_build/android-core/$android_abi"
jni_dir="$repo_root/mobile/Android/app/src/main/jniLibs/$android_abi"
library="$build_dir/libocaml_demo_core.so"

"$repo_root/scripts/bootstrap-android-ocaml.sh" >/dev/null
"$repo_root/scripts/build-journal-web.sh"

if [[ -d ${ANDROID_NDK_HOME:-} ]]; then
  ndk_root=$ANDROID_NDK_HOME
else
  ndk_root=
  for candidate in "$android_home"/ndk/*; do
    [[ -d $candidate ]] && ndk_root=$candidate
  done
fi
[[ -n ${ndk_root:-} && -d $ndk_root ]] || die "Android NDK is not installed under $android_home/ndk"

case "$(uname -s)" in
  Darwin)
    ndk_host=darwin-x86_64
    ;;
  Linux)
    ndk_host=linux-x86_64
    ;;
  *)
    die "unsupported build host: $(uname -s)"
    ;;
esac

ndk_bin="$ndk_root/toolchains/llvm/prebuilt/$ndk_host/bin"
ocamlopt="$target_prefix/bin/ocamlopt.opt"
ocaml_lib="$target_prefix/lib/ocaml"

mkdir -p "$build_dir" "$jni_dir"
"$repo_root/scripts/build-mobile-ocaml-deps.sh" \
  "$target_prefix" \
  "$build_dir"
dependency_dir="$build_dir/mobile-ocaml-deps"
dependency_objects=()
while IFS= read -r object; do
  dependency_objects+=("$object")
done <"$dependency_dir/link-objects.txt"
sqlite_stub_source=$(<"$dependency_dir/sqlite-stub-source.txt")
sqlite_source_dir=$("$repo_root/scripts/build-android-sqlite.sh")

cd "$build_dir"

"$ocamlopt" -I "$dependency_dir" -c -o ocaml_demo_model.cmi \
  "$repo_root/examples/shared/ocaml_demo_model.mli"
"$ocamlopt" -I . -I "$dependency_dir" -c -o ocaml_demo_model.cmx \
  "$repo_root/examples/shared/ocaml_demo_model.ml"
"$ocamlopt" -I . -c -o ocaml_demo_json.cmi \
  "$repo_root/examples/shared/ocaml_demo_json.mli"
"$ocamlopt" -I . -c -o ocaml_demo_json.cmx \
  "$repo_root/examples/shared/ocaml_demo_json.ml"
"$ocamlopt" -I . -I "$dependency_dir" -c -o ocaml_demo_rpc.cmi \
  "$repo_root/examples/shared/ocaml_demo_rpc.mli"
"$ocamlopt" -I . -I "$dependency_dir" -c -o ocaml_demo_rpc.cmx \
  "$repo_root/examples/shared/ocaml_demo_rpc.ml"
"$ocamlopt" -I . -I "$dependency_dir" -c -o ocaml_demo_sqlite.cmx \
  "$repo_root/mobile/core/ocaml_demo_sqlite.ml"
"$ocamlopt" -I . -I "$dependency_dir" -c -o ocaml_demo_mobile_entry.cmx \
  "$repo_root/mobile/core/ocaml_demo_mobile_entry.ml"

"$ocamlopt" \
  -I . \
  -runtime-variant _pic \
  -output-complete-obj \
  -linkall \
  -o ocaml_demo_runtime.o \
  str.cmxa \
  unix.cmxa \
  "${dependency_objects[@]}" \
  ocaml_demo_model.cmx \
  ocaml_demo_json.cmx \
  ocaml_demo_rpc.cmx \
  ocaml_demo_sqlite.cmx \
  ocaml_demo_mobile_entry.cmx

"$ndk_bin/clang" \
  --target="$target" \
  -fPIC \
  -I "$ocaml_lib" \
  -c "$repo_root/mobile/core/ocaml_demo_core_ffi.c" \
  -o ocaml_demo_core_ffi.o

"$ndk_bin/clang" \
  --target="$target" \
  -fPIC \
  -I "$ocaml_lib" \
  -I "$sqlite_source_dir" \
  -c "$sqlite_stub_source" \
  -o datascript_sqlite_stubs.o

"$ndk_bin/clang" \
  --target="$target" \
  -fPIC \
  -O2 \
  -D_FILE_OFFSET_BITS=64 \
  -DSQLITE_OMIT_LOAD_EXTENSION \
  -DSQLITE_THREADSAFE=1 \
  -c "$sqlite_source_dir/sqlite3.c" \
  -o sqlite3.o

"$ndk_bin/clang" \
  --target="$target" \
  -shared \
  -Wl,-soname,libocaml_demo_core.so \
  -o "$library" \
  ocaml_demo_runtime.o \
  ocaml_demo_core_ffi.o \
  datascript_sqlite_stubs.o \
  sqlite3.o \
  -lm \
  -ldl \
  -pthread

"$ndk_bin/llvm-strip" --strip-unneeded "$library"
cp "$library" "$jni_dir/libocaml_demo_core.so"

"$ndk_bin/llvm-readelf" -h "$library" \
  | grep "Machine:.*AArch64\\|Machine:.*Advanced Micro Devices X86-64" \
  >/dev/null
"$ndk_bin/llvm-readelf" -s "$library" | grep "ocaml_demo_call" >/dev/null

echo "$jni_dir/libocaml_demo_core.so"
