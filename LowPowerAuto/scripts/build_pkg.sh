#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="LowPowerAuto.app"
STAGE_DIR="$ROOT_DIR/dist/.staging"
APP_ROOT="$STAGE_DIR/$APP_NAME"
PKG_PATH="$ROOT_DIR/dist/LowPowerAutoInstaller.pkg"
BIN_SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/LowPowerAuto"
BCLM_SRC="$ROOT_DIR/vendor/bclm/.build/release/bclm"
BATT_SRC="$(command -v batt 2>/dev/null || true)"
if [[ -z "$BATT_SRC" || ! -x "$BATT_SRC" ]]; then
  for candidate in "/usr/local/bin/batt" "/opt/homebrew/bin/batt" "/Applications/batt.app/Contents/MacOS/batt"; do
    if [[ -x "$candidate" ]]; then
      BATT_SRC="$candidate"
      break
    fi
  done
fi
BATT_MODE="none"
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
if [[ -n "$BATT_SRC" && -x "$BATT_SRC" ]]; then
  cp "$BATT_SRC" "$APP_ROOT/Contents/Resources/batt"
  BATT_MODE="native"
else
  cat > "$APP_ROOT/Contents/Resources/batt" <<'BATT'
#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
BCLM="$SELF_DIR/bclm"

if [[ ! -x "$BCLM" ]]; then
  echo "batt shim: bundled bclm not found at $BCLM" >&2
  exit 1
fi

case "${1:-}" in
  limit)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: batt limit <percent>" >&2
      exit 2
    fi
    exec "$BCLM" write "$2"
    ;;
  disable)
    exec "$BCLM" write "100"
    ;;
  *)
    echo "Usage: batt {limit <percent>|disable}" >&2
    exit 2
    ;;
esac
BATT
  BATT_MODE="shim"
fi
chmod +x "$APP_ROOT/Contents/MacOS/LowPowerAuto" "$APP_ROOT/Contents/Resources/bclm"
if [[ -f "$APP_ROOT/Contents/Resources/batt" ]]; then
  chmod +x "$APP_ROOT/Contents/Resources/batt"
fi

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

if [[ "$BATT_MODE" == "native" ]]; then
  echo "Built installer with native batt + bclm backends: $PKG_PATH"
elif [[ "$BATT_MODE" == "shim" ]]; then
  echo "Built installer with batt shim + bclm backends: $PKG_PATH"
else
  echo "Built installer: $PKG_PATH"
fi
