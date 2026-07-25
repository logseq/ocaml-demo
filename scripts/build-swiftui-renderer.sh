#!/usr/bin/env bash
set -euo pipefail

SDK_NAME="${SWIFT_SDK:-iphonesimulator}"
TARGET="${SWIFT_TARGET:-${IOS_TARGET:-arm64-apple-ios17.0-simulator}}"
SDKROOT="${SWIFT_SDKROOT:-${IOS_SDKROOT:-$(xcrun --sdk "$SDK_NAME" --show-sdk-path)}}"
SOURCE="${SWIFT_SOURCE:-apple/swiftui/OCamlDemoSwiftUI.swift}"
OUTPUT="${1:-/tmp/OCamlDemoSwiftUI.o}"
if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$PWD/$OUTPUT"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

xcrun swiftc \
  -target "$TARGET" \
  -sdk "$SDKROOT" \
  ${SWIFT_FLAGS:-} \
  -parse-as-library \
  -emit-object \
  "$REPO_ROOT/$SOURCE" \
  -o "$OUTPUT"
