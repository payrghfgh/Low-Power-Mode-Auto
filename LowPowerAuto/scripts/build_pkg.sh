#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="LowPowerAuto.app"
STAGE_DIR="$ROOT_DIR/dist/.staging"
APP_ROOT="$STAGE_DIR/$APP_NAME"
PKG_PATH="$ROOT_DIR/dist/LowPowerAutoInstaller.pkg"
BIN_SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/LowPowerAuto"
BCLM_SRC="$ROOT_DIR/vendor/bclm/.build/release/bclm"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
PKG_SIGN_IDENTITY="${PKG_SIGN_IDENTITY:-}"

cd "$ROOT_DIR"

swift build
swift build -c release --package-path "$ROOT_DIR/vendor/bclm"

mkdir -p "$STAGE_DIR"
rm -rf "$APP_ROOT" "$PKG_PATH"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"
cp "$BIN_SRC" "$APP_ROOT/Contents/MacOS/LowPowerAuto"
cp "$BCLM_SRC" "$APP_ROOT/Contents/Resources/bclm"
chmod +x "$APP_ROOT/Contents/MacOS/LowPowerAuto" "$APP_ROOT/Contents/Resources/bclm"

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

codesign --force --deep --sign "$APP_SIGN_IDENTITY" "$APP_ROOT"

PKG_ARGS=(
  --component "$APP_ROOT" \
  --install-location "/Applications" \
  --identifier "com.lowpowermode.auto" \
  --version "1.0.0"
)

if [[ -n "$PKG_SIGN_IDENTITY" ]]; then
  PKG_ARGS+=(--sign "$PKG_SIGN_IDENTITY")
fi

PKG_ARGS+=("$PKG_PATH")

pkgbuild "${PKG_ARGS[@]}"

pkgutil --check-signature "$PKG_PATH" || true

echo "Built installer: $PKG_PATH"
