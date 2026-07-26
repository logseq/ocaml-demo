#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ocaml_version=${OCAML_DEMO_IOS_OCAML_VERSION:-5.5.0}
deployment_target=${OCAML_DEMO_IOS_DEPLOYMENT_TARGET:-17.0}
jobs=${OCAML_DEMO_BUILD_JOBS:-8}
swift_target="arm64-apple-ios${deployment_target}"
configure_target=aarch64-apple-darwin
toolchain_root="$repo_root/_build/ios-toolchain"
host_prefix="$toolchain_root/host-$ocaml_version"
target_prefix="$toolchain_root/$swift_target-$ocaml_version"
host_source="$toolchain_root/ocaml-$ocaml_version-host"
target_source="$toolchain_root/ocaml-$ocaml_version-device"

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $(uname -s) == Darwin ]] || die "the iOS toolchain requires macOS"
command -v xcrun >/dev/null 2>&1 || die "xcrun was not found"

sdk_path=$(xcrun --sdk iphoneos --show-sdk-path)
clang=$(xcrun --sdk iphoneos --find clang)
ar=$(xcrun --sdk iphoneos --find ar)
ld=$(xcrun --sdk iphoneos --find ld)
ranlib=$(xcrun --sdk iphoneos --find ranlib)
strip=$(xcrun --sdk iphoneos --find strip)

mkdir -p "$toolchain_root"

clone_release() {
  local destination=$1
  if [[ ! -e $destination/.git ]]; then
    git clone --depth 1 --branch "$ocaml_version" \
      https://github.com/ocaml/ocaml.git \
      "$destination"
  fi
}

build_host_compiler() {
  clone_release "$host_source"
  (
    cd "$host_source"
    ./configure \
      --disable-ocamldoc \
      --disable-ocamltest \
      --disable-stdlib-manpages \
      --prefix="$host_prefix"
    make -j"$jobs"
    make install
  )
}

build_target_compiler() {
  clone_release "$target_source"
  (
    cd "$target_source"
    PATH="$host_prefix/bin:$PATH" \
      ac_cv_func_getentropy=no \
      ac_cv_func_system=no \
      ./configure \
      --disable-dependency-generation \
      --disable-function-sections \
      --disable-shared \
      --disable-warn-error \
      --prefix="$target_prefix" \
      --target="$configure_target" \
      --without-zstd \
      TARGET_LIBDIR=/dummy/directory \
      CC="$clang -target $swift_target -isysroot $sdk_path" \
      AR="$ar" \
      DIRECT_LD="$ld" \
      LD="$ld" \
      PARTIALLD="$ld -r" \
      RANLIB="$ranlib" \
      STRIP="$strip"
    PATH="$host_prefix/bin:$PATH" make crossopt -j"$jobs"
    PATH="$host_prefix/bin:$PATH" make installcross
  )
}

if [[ ! -x $host_prefix/bin/ocamlopt.opt ]]; then
  build_host_compiler
fi

host_version=$("$host_prefix/bin/ocamlopt.opt" -version)
[[ $host_version == "$ocaml_version" ]] \
  || die "host compiler version is $host_version, expected $ocaml_version"

if [[ ! -x $target_prefix/bin/ocamlopt.opt ]]; then
  build_target_compiler
fi

target_version=$("$target_prefix/bin/ocamlopt.opt" -version)
[[ $target_version == "$ocaml_version" ]] \
  || die "target compiler version is $target_version, expected $ocaml_version"

echo "$target_prefix"
