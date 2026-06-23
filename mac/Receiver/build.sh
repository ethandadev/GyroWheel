#!/usr/bin/env bash
#
# Builds the GyroWheel Receiver desktop app and ad-hoc signs it with the
# virtual-HID entitlement (works once SIP + AMFI are disabled for personal use).
# Opens the built app when done.
#
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
    brew install xcodegen
fi

echo "Generating project…"
xcodegen generate

echo "Building (ad-hoc signed)…"
xcodebuild -project GyroWheelReceiver.xcodeproj -scheme GyroWheelReceiver \
    -configuration Release -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO \
    build | tail -3

APP="build/Build/Products/Release/GyroWheelReceiver.app"
echo "✅ Built $APP"
echo "Launching…"
open "$APP"
echo
echo "If 'Start' shows an error, SIP/AMFI aren't disabled yet (personal-use"
echo "requirement). Otherwise: press Start, then enter the shown IP on the phone."
