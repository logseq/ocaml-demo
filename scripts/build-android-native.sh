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
cd "$build_dir"

"$ocamlopt" -c -o ocaml_demo_model.cmi \
  "$repo_root/examples/shared/ocaml_demo_model.mli"
"$ocamlopt" -I . -c -o ocaml_demo_model.cmx \
  "$repo_root/examples/shared/ocaml_demo_model.ml"
"$ocamlopt" -I . -c -o ocaml_demo_json.cmi \
  "$repo_root/mobile/core/ocaml_demo_json.mli"
"$ocamlopt" -I . -c -o ocaml_demo_json.cmx \
  "$repo_root/mobile/core/ocaml_demo_json.ml"
"$ocamlopt" -I . -c -o ocaml_demo_mobile_rpc.cmi \
  "$repo_root/mobile/core/ocaml_demo_mobile_rpc.mli"
"$ocamlopt" -I . -c -o ocaml_demo_mobile_rpc.cmx \
  "$repo_root/mobile/core/ocaml_demo_mobile_rpc.ml"
"$ocamlopt" -I . -c -o ocaml_demo_mobile_entry.cmx \
  "$repo_root/mobile/core/ocaml_demo_mobile_entry.ml"

"$ocamlopt" \
  -I . \
  -runtime-variant _pic \
  -output-complete-obj \
  -linkall \
  -o ocaml_demo_runtime.o \
  ocaml_demo_model.cmx \
  ocaml_demo_json.cmx \
  ocaml_demo_mobile_rpc.cmx \
  ocaml_demo_mobile_entry.cmx

"$ndk_bin/clang" \
  --target="$target" \
  -fPIC \
  -I "$ocaml_lib" \
  -c "$repo_root/mobile/core/ocaml_demo_core_ffi.c" \
  -o ocaml_demo_core_ffi.o

"$ndk_bin/clang" \
  --target="$target" \
  -shared \
  -Wl,-soname,libocaml_demo_core.so \
  -o "$library" \
  ocaml_demo_runtime.o \
  ocaml_demo_core_ffi.o \
  -lm \
  -ldl \
  -pthread

"$ndk_bin/llvm-strip" --strip-unneeded "$library"
cp "$library" "$jni_dir/libocaml_demo_core.so"

"$ndk_bin/llvm-readelf" -h "$library" | grep -q "Machine:.*AArch64\\|Machine:.*Advanced Micro Devices X86-64"
"$ndk_bin/llvm-readelf" -s "$library" | grep -q "ocaml_demo_call"

echo "$jni_dir/libocaml_demo_core.so"
