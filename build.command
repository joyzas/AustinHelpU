#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p Build
STAGING="$(mktemp -d "$PWD/Build/staging.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/AustinHelpU.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK_PATH="$(xcrun --show-sdk-path)"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
swiftc -swift-version 5 -parse-as-library -sdk "$SDK_PATH" \
  -target arm64-apple-macosx14.0 \
  -module-cache-path /tmp/xiaozhang-swift-cache \
  Models.swift Browser.swift Proxy.swift AppModel.swift Views.swift Main.swift \
  -o "$APP/Contents/MacOS/AustinHelpU"
for resource in AppIcon.icns brand.png products.json stores.json; do
  cp "Resources/$resource" "$APP/Contents/Resources/"
done
cp LICENSE NOTICE THIRD_PARTY.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>AustinHelpU</string>
<key>CFBundleDisplayName</key><string>AustinHelpU</string>
<key>CFBundleIdentifier</key><string>cn.xiaozhang.watch</string>
<key>CFBundleExecutable</key><string>AustinHelpU</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.6</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
rm -rf "$PWD/Build/AustinHelpU.app"
mv "$APP" "$PWD/Build/AustinHelpU.app"
APP="$PWD/Build/AustinHelpU.app"
echo "已构建：$APP"
