#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mobile_root="$repo_root/mobile"
ocaml_version=${OCAML_DEMO_IOS_OCAML_VERSION:-5.5.0}
deployment_target=${OCAML_DEMO_IOS_DEPLOYMENT_TARGET:-17.0}
sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
triple="arm64-apple-ios${deployment_target}-simulator"
swift_build_dir="$mobile_root/.build/arm64-apple-ios-simulator/debug"
target_prefix="$repo_root/_build/ios-toolchain/$triple-$ocaml_version"
core_build_dir="$repo_root/_build/ios-core/simulator"
core_object="$core_build_dir/ocaml_demo_runtime.o"
ffi_object="$core_build_dir/ocaml_demo_core_ffi.o"
app_dir="$mobile_root/.build/OCamlDemo.app"
frameworks_dir="$app_dir/Frameworks"

"$repo_root/scripts/bootstrap-ios-ocaml.sh" >/dev/null

ocamlopt="$target_prefix/bin/ocamlopt.opt"
ocaml_lib="$target_prefix/lib/ocaml"
clang=$(xcrun --sdk iphonesimulator --find clang)

mkdir -p "$core_build_dir"
cd "$core_build_dir"

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
  -output-complete-obj \
  -linkall \
  -o "$core_object" \
  ocaml_demo_model.cmx \
  ocaml_demo_json.cmx \
  ocaml_demo_mobile_rpc.cmx \
  ocaml_demo_mobile_entry.cmx

"$clang" \
  -target "$triple" \
  -isysroot "$sdk_path" \
  -fPIC \
  -I "$ocaml_lib" \
  -c "$repo_root/mobile/core/ocaml_demo_core_ffi.c" \
  -o "$ffi_object"

swift build \
  --disable-keychain \
  --package-path "$mobile_root" \
  --triple "$triple" \
  --sdk "$sdk_path" \
  -Xswiftc -DOCAML_DEMO_CORE \
  -Xlinker "$core_object" \
  -Xlinker "$ffi_object"

mkdir -p "$frameworks_dir"
cp "$mobile_root/Darwin/Info.plist" "$app_dir/Info.plist"
cp "$swift_build_dir/libOCamlDemo.dylib" "$frameworks_dir/libOCamlDemo.dylib"

for bundle in "$swift_build_dir"/*.bundle; do
  [[ -d "$bundle" ]] || continue
  cp -R "$bundle" "$app_dir/"
done

xcrun --sdk iphonesimulator swiftc \
  -parse-as-library \
  -module-name OCamlDemoShell \
  -target "$triple" \
  -sdk "$sdk_path" \
  -I "$swift_build_dir/Modules" \
  -Xcc "-fmodule-map-file=$swift_build_dir/OCamlCoreABI.build/module.modulemap" \
  -Xcc "-I$mobile_root/Sources/OCamlCoreABI/include" \
  -L "$swift_build_dir" \
  -lOCamlDemo \
  -framework SwiftUI \
  -framework UIKit \
  -Xlinker -rpath \
  -Xlinker @executable_path/Frameworks \
  "$mobile_root/Darwin/Sources/Main.swift" \
  -o "$app_dir/OCamlDemo"

codesign --force --sign - --timestamp=none "$frameworks_dir/libOCamlDemo.dylib"
codesign --force --sign - --timestamp=none "$app_dir"

echo "$app_dir"
