#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-${LOWPOWERAUTO_REPO:-}}"

if [[ -z "$REPO" ]]; then
  echo "Usage: sudo ./scripts/install_latest_from_github.sh <owner/repo>"
  echo "Example: sudo ./scripts/install_latest_from_github.sh rushian/lowpowerauto"
  exit 2
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Please run with sudo."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
PKG_PATH="$TMP_DIR/LowPowerAutoInstaller.pkg"
PKG_URL="https://github.com/$REPO/releases/latest/download/LowPowerAutoInstaller.pkg"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading: $PKG_URL"
curl -fL "$PKG_URL" -o "$PKG_PATH"

echo "Installing package..."
installer -pkg "$PKG_PATH" -target /

echo "Installed LowPowerAuto from GitHub release: $REPO"
