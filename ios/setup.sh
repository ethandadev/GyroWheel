#!/usr/bin/env bash
#
# One-command project setup for the GyroWheel iOS app.
# Installs XcodeGen (if needed), generates GyroWheel.xcodeproj, opens Xcode.
#
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen not found — installing via Homebrew…"
    if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: Homebrew is required. Install it from https://brew.sh and re-run."
        exit 1
    fi
    brew install xcodegen
fi

echo "Generating GyroWheel.xcodeproj…"
xcodegen generate

echo "Opening in Xcode…"
open GyroWheel.xcodeproj

cat <<'EOF'

────────────────────────────────────────────────────────────────────
 Final steps in Xcode (one time):
   1. Click the "GyroWheel" target → "Signing & Capabilities" tab.
   2. Tick "Automatically manage signing" and choose your Team.
      (No team? Xcode → Settings → Accounts → "+" → add your Apple ID,
       then pick the "(Personal Team)" that appears.)
   3. If you get a "bundle identifier is not available" error, change
      PRODUCT_BUNDLE_IDENTIFIER to something unique, e.g.
      com.YOURNAME.GyroWheel (edit project.yml then re-run this script,
      or just edit it in the Xcode UI).
   4. Plug in your iPhone via USB and pick it in the device dropdown
      (top toolbar, next to the Run button).
   5. Press ⌘R to build & install.
   6. First launch only — on the iPhone:
      Settings → General → VPN & Device Management → tap your developer
      certificate → Trust. Then reopen the app.

 Note: apps signed with a free Apple ID expire after 7 days — just hit
 ⌘R again to reinstall. A paid Apple Developer account lasts a year.
────────────────────────────────────────────────────────────────────
EOF
