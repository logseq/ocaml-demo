#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mobile_root="$repo_root/mobile"
ocaml_version=${OCAML_DEMO_IOS_OCAML_VERSION:-5.5.0}
deployment_target=${OCAML_DEMO_IOS_DEPLOYMENT_TARGET:-17.0}
sdk_path=$(xcrun --sdk iphoneos --show-sdk-path)
triple="arm64-apple-ios${deployment_target}"
swift_build_dir="$mobile_root/.build/arm64-apple-ios/debug"
target_prefix="$repo_root/_build/ios-toolchain/$triple-$ocaml_version"
core_build_dir="$repo_root/_build/ios-core/device"
core_object="$core_build_dir/ocaml_demo_runtime.o"
ffi_object="$core_build_dir/ocaml_demo_core_ffi.o"
sqlite_object="$core_build_dir/datascript_sqlite_stubs.o"
app_dir="$mobile_root/.build/OCamlDemo-device.app"
frameworks_dir="$app_dir/Frameworks"
profile=${OCAML_DEMO_IOS_PROFILE:-"$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/472c0f2f-8c2a-4190-a118-197254f6079d.mobileprovision"}
signing_identity=${OCAML_DEMO_IOS_SIGNING_IDENTITY:-3BD54F6A1F7C4DEAAC47F3842AD01A8173173282}

die() {
  echo "error: $*" >&2
  exit 1
}

[[ -f $profile ]] || die "provisioning profile was not found: $profile"

"$repo_root/scripts/bootstrap-ios-device-ocaml.sh" >/dev/null
"$repo_root/scripts/build-journal-web.sh"

ocamlopt="$target_prefix/bin/ocamlopt.opt"
ocaml_lib="$target_prefix/lib/ocaml"
clang=$(xcrun --sdk iphoneos --find clang)

mkdir -p "$core_build_dir"
"$repo_root/scripts/build-mobile-ocaml-deps.sh" \
  "$target_prefix" \
  "$core_build_dir"
dependency_dir="$core_build_dir/mobile-ocaml-deps"
dependency_objects=()
while IFS= read -r object; do
  dependency_objects+=("$object")
done <"$dependency_dir/link-objects.txt"
sqlite_stub_source=$(<"$dependency_dir/sqlite-stub-source.txt")

cd "$core_build_dir"

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
  -output-complete-obj \
  -linkall \
  -o "$core_object" \
  str.cmxa \
  unix.cmxa \
  "${dependency_objects[@]}" \
  ocaml_demo_model.cmx \
  ocaml_demo_json.cmx \
  ocaml_demo_rpc.cmx \
  ocaml_demo_sqlite.cmx \
  ocaml_demo_mobile_entry.cmx

"$clang" \
  -target "$triple" \
  -isysroot "$sdk_path" \
  -fPIC \
  -I "$ocaml_lib" \
  -c "$repo_root/mobile/core/ocaml_demo_core_ffi.c" \
  -o "$ffi_object"

"$clang" \
  -target "$triple" \
  -isysroot "$sdk_path" \
  -fPIC \
  -I "$ocaml_lib" \
  -c "$sqlite_stub_source" \
  -o "$sqlite_object"

rm -f "$swift_build_dir/libOCamlDemo.dylib"
swift build \
  --disable-keychain \
  --package-path "$mobile_root" \
  --triple "$triple" \
  --sdk "$sdk_path" \
  -Xswiftc -DOCAML_DEMO_CORE \
  -Xlinker "$core_object" \
  -Xlinker "$ffi_object" \
  -Xlinker "$sqlite_object" \
  -Xlinker -lsqlite3

rm -rf "$app_dir"
mkdir -p "$frameworks_dir"
cp "$mobile_root/Darwin/Info.plist" "$app_dir/Info.plist"
cp "$profile" "$app_dir/embedded.mobileprovision"
cp "$swift_build_dir/libOCamlDemo.dylib" "$frameworks_dir/libOCamlDemo.dylib"

for bundle in "$swift_build_dir"/*.bundle; do
  [[ -d "$bundle" ]] || continue
  cp -R "$bundle" "$app_dir/"
done

xcrun --sdk iphoneos swiftc \
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

profile_plist=$(mktemp)
entitlements=$(mktemp)
trap 'rm -f "$profile_plist" "$entitlements"' EXIT
security cms -D -i "$profile" >"$profile_plist"
plutil -extract Entitlements xml1 -o "$entitlements" "$profile_plist"
plutil -replace application-identifier \
  -string K378MFWK59.com.logseq.ocamldemo \
  "$entitlements"

codesign --force --sign "$signing_identity" --timestamp=none \
  "$frameworks_dir/libOCamlDemo.dylib"
codesign --force --sign "$signing_identity" --timestamp=none \
  --entitlements "$entitlements" \
  "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
