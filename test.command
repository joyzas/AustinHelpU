#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
rotation_flags=(-swift-version 5 -module-cache-path /tmp/xiaozhang-swift-cache)
if [ "$(uname -s)" = "Darwin" ]; then
  sdk="$(xcrun --show-sdk-path)"
  if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
  rotation_flags+=(-sdk "$sdk" -target arm64-apple-macosx14.0)
fi
rotation_test="$(mktemp -d)"
trap 'rm -rf "$rotation_test"' EXIT
swiftc "${rotation_flags[@]}" -parse-as-library NodeRotation.swift RotationTests.swift -o "$rotation_test/rotation-tests"
"$rotation_test/rotation-tests"
if [ "${1:-}" = "--rotation" ]; then exit 0; fi
sdk="$(xcrun --show-sdk-path)"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
swiftc -swift-version 5 -sdk "$sdk" -module-cache-path /tmp/xiaozhang-swift-cache -parse-as-library NodeRotation.swift Models.swift Browser.swift Proxy.swift Tests.swift -o /tmp/xiaozhang-tests
/tmp/xiaozhang-tests
if [ "${1:-}" = "--browser" ]; then
  swiftc -swift-version 5 -sdk "$sdk" -module-cache-path /tmp/xiaozhang-swift-cache -parse-as-library NodeRotation.swift Models.swift Browser.swift BrowserTests.swift -o /tmp/austin-browser-tests
  /tmp/austin-browser-tests
fi
