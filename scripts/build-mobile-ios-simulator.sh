#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mobile_root="$repo_root/mobile"
sdk_path=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.0.sdk
triple=arm64-apple-ios17.0-simulator
swift_build_dir="$mobile_root/.build/arm64-apple-ios-simulator/debug"
core_object="$repo_root/_build/simulator.ios/mobile/core/ocaml_demo_mobile_entry.exe.o"
app_dir="$mobile_root/.build/OCamlDemo.app"
frameworks_dir="$app_dir/Frameworks"

opam exec -- dune build mobile/core/ocaml_demo_mobile_entry.exe.o \
  --workspace dune-workspace.simulator

swift build \
  --disable-keychain \
  --package-path "$mobile_root" \
  --triple "$triple" \
  --sdk "$sdk_path" \
  -Xswiftc -DOCAML_DEMO_CORE \
  -Xlinker "$core_object"

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
