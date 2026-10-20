#!/bin/bash
# Builds ClipBar.app (no Xcode needed, Command Line Tools are enough) and launches it.
#   ./build.sh                       ad-hoc signature
#   SIGN_ID="ClipBar Dev" ./build.sh   sign with a self-signed cert
set -euo pipefail
cd "$(dirname "$0")"

APP="ClipBar.app"
SIGN_ID="${SIGN_ID:--}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClipBar"

# Stop the running copy and wait until it is really gone (avoids LaunchServices error -600)
pkill -x ClipBar 2>/dev/null || true
while pgrep -x ClipBar >/dev/null; do sleep 0.1; done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipBar"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Icon skipped for now. To add one later: put Resources/AppIcon.icns in place, copy it to
# "$APP/Contents/Resources/" here and add <key>CFBundleIconFile</key><string>AppIcon</string> to the plist.

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.anish.clipbar</string>
  <key>CFBundleName</key><string>ClipBar</string>
  <key>CFBundleDisplayName</key><string>ClipBar</string>
  <key>CFBundleExecutable</key><string>ClipBar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign "$SIGN_ID" "$APP"
sleep 0.5
open "$APP"
echo "Launched $APP"
