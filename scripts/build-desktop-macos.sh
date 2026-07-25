#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mobile_root="$repo_root/mobile"
arch=$(uname -m)
target="$arch-apple-macosx14.0"
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
swift_build_dir="$mobile_root/.build/$arch-apple-macosx/debug"
core_build_dir="$repo_root/_build/macos-core/$arch"
core_object="$core_build_dir/ocaml_demo_runtime.o"
ffi_object="$core_build_dir/ocaml_demo_core_ffi.o"
app_dir="$mobile_root/.build/OCamlDemoMac.app"
contents_dir="$app_dir/Contents"
frameworks_dir="$contents_dir/Frameworks"
macos_dir="$contents_dir/MacOS"

if [[ -n ${OCAML_DEMO_HOST_OCAMLOPT:-} ]]; then
  ocamlopt=$OCAML_DEMO_HOST_OCAMLOPT
else
  ocamlopt="$(opam var bin)/ocamlopt.opt"
fi
ocaml_lib=$("$ocamlopt" -where)
clang=$(xcrun --sdk macosx --find clang)

mkdir -p "$core_build_dir"
cd "$core_build_dir"

"$ocamlopt" -c -o ocaml_demo_model.cmi \
  "$repo_root/examples/shared/ocaml_demo_model.mli"
"$ocamlopt" -I . -c -o ocaml_demo_model.cmx \
  "$repo_root/examples/shared/ocaml_demo_model.ml"
"$ocamlopt" -I . -c -o ocaml_demo_json.cmi \
  "$repo_root/examples/shared/ocaml_demo_json.mli"
"$ocamlopt" -I . -c -o ocaml_demo_json.cmx \
  "$repo_root/examples/shared/ocaml_demo_json.ml"
"$ocamlopt" -I . -c -o ocaml_demo_rpc.cmi \
  "$repo_root/examples/shared/ocaml_demo_rpc.mli"
"$ocamlopt" -I . -c -o ocaml_demo_rpc.cmx \
  "$repo_root/examples/shared/ocaml_demo_rpc.ml"
"$ocamlopt" -I . -c -o ocaml_demo_mobile_entry.cmx \
  "$repo_root/mobile/core/ocaml_demo_mobile_entry.ml"

"$ocamlopt" \
  -I . \
  -runtime-variant _pic \
  -output-complete-obj \
  -linkall \
  -o "$core_object" \
  ocaml_demo_model.cmx \
  ocaml_demo_json.cmx \
  ocaml_demo_rpc.cmx \
  ocaml_demo_mobile_entry.cmx

"$clang" \
  -target "$target" \
  -isysroot "$sdk_path" \
  -fPIC \
  -I "$ocaml_lib" \
  -c "$repo_root/mobile/core/ocaml_demo_core_ffi.c" \
  -o "$ffi_object"

swift build \
  --disable-keychain \
  --package-path "$mobile_root" \
  --triple "$target" \
  --sdk "$sdk_path" \
  -Xswiftc -DOCAML_DEMO_CORE \
  -Xlinker "$core_object" \
  -Xlinker "$ffi_object"

rm -rf "$app_dir"
mkdir -p "$frameworks_dir" "$macos_dir"
cp "$mobile_root/Darwin/Info.macos.plist" "$contents_dir/Info.plist"
cp "$swift_build_dir/libOCamlDemo.dylib" "$frameworks_dir/libOCamlDemo.dylib"

for bundle in "$swift_build_dir"/*.bundle; do
  [[ -d $bundle ]] || continue
  case "$(basename "$bundle")" in
    *Tests.bundle|skip-unit_*.bundle)
      continue
      ;;
  esac
  cp -R "$bundle" "$app_dir/"
done

xcrun --sdk macosx swiftc \
  -parse-as-library \
  -module-name OCamlDemoShell \
  -target "$target" \
  -sdk "$sdk_path" \
  -I "$swift_build_dir/Modules" \
  -Xcc "-fmodule-map-file=$swift_build_dir/OCamlCoreABI.build/module.modulemap" \
  -Xcc "-I$mobile_root/Sources/OCamlCoreABI/include" \
  -L "$swift_build_dir" \
  -lOCamlDemo \
  -framework SwiftUI \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  "$mobile_root/Darwin/Sources/Main.swift" \
  -o "$macos_dir/OCamlDemo"

echo "$app_dir"
