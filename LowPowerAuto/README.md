# LowPowerAuto (macOS)

A small menu bar app that monitors battery percentage and enables macOS Low Power Mode when battery drops below your chosen threshold.

## What it does

- Runs in the menu bar.
- Monitors battery percentage in real time.
- Lets you set a threshold (5-100%).
- Can launch automatically at login.
- When battery percentage is below threshold, it enables Low Power Mode.
- When battery percentage rises above threshold, it disables Low Power Mode.
- Can set a battery charge limit (for example 80%) to stop charging above that level.
- Supports one-time passwordless setup so you do not get repeated admin prompts.
- Includes `Force Low Power` and `Force Normal` controls.
- Includes onboarding, diagnostics panel, and daily battery stats.
- Includes update checks against GitHub latest release.

## Build and run

### Option 1 (recommended): Xcode

1. Open `/Users/rushian/LOW POWER MODE/LowPowerAuto/Package.swift` in Xcode.
2. Choose the `LowPowerAuto` scheme.
3. Run.

### Option 2: Terminal

```bash
cd "/Users/rushian/LOW POWER MODE/LowPowerAuto"
swift run
```

## Install as normal app

```bash
cd "/Users/rushian/LOW POWER MODE/LowPowerAuto"
./scripts/install_app.sh
```

This installs `LowPowerAuto.app` into `/Applications`.

## Install latest from GitHub (sudo)

After you publish a release containing `LowPowerAutoInstaller.pkg`, users can install with:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/LowPowerAuto/scripts/install_latest_from_github.sh | sudo bash -s -- <owner>/<repo>
```

Example:

```bash
curl -fsSL https://raw.githubusercontent.com/rushian/lowpowerauto/main/LowPowerAuto/scripts/install_latest_from_github.sh | sudo bash -s -- rushian/lowpowerauto
```

## Build a proper installer (.pkg)

```bash
cd "/Users/rushian/LOW POWER MODE/LowPowerAuto"
./scripts/build_pkg.sh
```

Output package:

`/Users/rushian/LOW POWER MODE/LowPowerAuto/dist/LowPowerAutoInstaller.pkg`

## GitHub release automation

- Workflow file: `.github/workflows/release-pkg.yml`
- Trigger: push a tag like `v1.0.0`
- Result: builds `LowPowerAutoInstaller.pkg` and uploads it to the GitHub Release

### Signed package (optional)

```bash
cd "/Users/rushian/LOW POWER MODE/LowPowerAuto"
APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PKG_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
./scripts/build_pkg.sh
```

### Notarize package (optional)

```bash
cd "/Users/rushian/LOW POWER MODE/LowPowerAuto"
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
./scripts/notarize_pkg.sh
```

## Notes

- `Launch at login` can be toggled directly inside the app.
- For no repeated password prompts, click `Enable passwordless control (one-time)` in the app once.
- That setup writes `/etc/sudoers.d/lowpowerauto` with limited rules for `pmset`, bundled `bclm`, and `batt`.
- Charge limit uses bundled `batt` first (`batt limit` / `batt disable`), then bundled `bclm`, then `pmset` fallback.
- Installer bundles native `batt` when available, otherwise a bundled `batt` shim that forwards to bundled `bclm`.
- On Apple silicon, hardware limits only allow `80` or `100` as effective charge cap values.
- If hardware charge-stop is blocked by the OS, the app falls back to software monitoring and sends a threshold alert to unplug the charger.
- If your command line Swift toolchain and macOS SDK versions are mismatched, run through Xcode (uses integrated toolchain management).
