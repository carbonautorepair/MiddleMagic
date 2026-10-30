#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --configuration release --product MiddlePaste
APP="dist/MiddleMagic.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MiddlePaste "$APP/Contents/MacOS/MiddlePaste"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.middlemagic.app</string>
  <key>CFBundleName</key><string>MiddleMagic</string>
  <key>CFBundleExecutable</key><string>MiddlePaste</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Ad hoc signing for local use. Set SIGN_ID to a code-signing identity to keep
# Accessibility permission stable across rebuilds.
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"
