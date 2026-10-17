#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="$(xcrun --show-sdk-path)"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
swiftc -swift-version 5 -sdk "$sdk" -module-cache-path /tmp/xiaozhang-swift-cache -parse-as-library Models.swift Browser.swift Proxy.swift Tests.swift -o /tmp/xiaozhang-tests
/tmp/xiaozhang-tests
if [ "${1:-}" = "--browser" ]; then
  swiftc -swift-version 5 -sdk "$sdk" -module-cache-path /tmp/xiaozhang-swift-cache -parse-as-library Models.swift Browser.swift BrowserTests.swift -o /tmp/austin-browser-tests
  /tmp/austin-browser-tests
fi
