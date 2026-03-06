#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="LowPowerAuto.app"
APP_ROOT="$ROOT_DIR/dist/$APP_NAME"
BIN_SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/LowPowerAuto"
BCLM_SRC="$ROOT_DIR/vendor/bclm/.build/release/bclm"

cd "$ROOT_DIR"
swift build
swift build -c release --package-path "$ROOT_DIR/vendor/bclm"

rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"
cp "$BIN_SRC" "$APP_ROOT/Contents/MacOS/LowPowerAuto"
cp "$BCLM_SRC" "$APP_ROOT/Contents/Resources/bclm"
chmod +x "$APP_ROOT/Contents/Resources/bclm"

cat > "$APP_ROOT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>LowPowerAuto</string>
  <key>CFBundleExecutable</key>
  <string>LowPowerAuto</string>
  <key>CFBundleIdentifier</key>
  <string>com.lowpowermode.auto</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LowPowerAuto</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_ROOT"
rm -rf "/Applications/$APP_NAME"
cp -R "$APP_ROOT" "/Applications/$APP_NAME"
codesign --force --deep --sign - "/Applications/$APP_NAME"

codesign --verify --deep --strict "/Applications/$APP_NAME"

echo "Installed /Applications/$APP_NAME with bundled bclm backend"
