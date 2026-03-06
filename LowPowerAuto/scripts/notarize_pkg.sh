#!/usr/bin/env bash
set -euo pipefail

# Required env vars:
# APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
# Optional: PKG_PATH

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_PATH="${PKG_PATH:-$ROOT_DIR/dist/LowPowerAutoInstaller.pkg}"

if [[ ! -f "$PKG_PATH" ]]; then
  echo "Package not found: $PKG_PATH"
  exit 1
fi

: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD}"

xcrun notarytool submit "$PKG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

xcrun stapler staple "$PKG_PATH"

spctl -a -v --type install "$PKG_PATH" || true

echo "Notarized and stapled: $PKG_PATH"
