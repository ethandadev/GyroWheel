#!/usr/bin/env bash
#
# Generates GamepadReceiver.xcodeproj (host app + DriverKit extension) and
# opens it in Xcode. You then set your Team on both targets and hit Run.
#
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen not found — installing via Homebrew…"
    command -v brew >/dev/null 2>&1 || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
    brew install xcodegen
fi

echo "Generating GamepadReceiver.xcodeproj…"
xcodegen generate
open GamepadReceiver.xcodeproj

cat <<'EOF'

────────────────────────────────────────────────────────────────────────────
 You have a paid Developer account — here's the rest, in order:

 1. ENTITLEMENT REQUEST (do this first; Apple approval can take a few days)
    The DriverKit + HID entitlements are "managed" — request them once at:
      https://developer.apple.com/contact/request/system-extension/
    Ask for: DriverKit, DriverKit Transport: HID, DriverKit Family: HID.
    (System Extension itself you can enable yourself in the next step.)

 2. SIGNING (in Xcode, once)
    • Select the GamepadReceiver target → Signing & Capabilities →
      Automatically manage signing → pick your Team.
    • Same for the VirtualGamepadDriver target.
    • If Xcode says the DriverKit/HID entitlements aren't allowed, that's
      step 1 still pending — you can keep going once approved.

 3. ENABLE LOCAL DEXT LOADING (Terminal, once; needs a reboot)
      systemextensionsctl developer on
    (Lets your locally-built, dev-signed extension load without notarization.)

 4. RUN
    • Press ⌘R in Xcode to launch GamepadReceiver.
    • Click "Install / Activate", then approve the extension in
      System Settings → General → Login Items & Extensions → Driver Extensions.
    • Status dot turns green → click "Start" (UDP 5005).

 5. VERIFY  →  open any gamepad tester; you'll see "GyroWheel Virtual Gamepad".
    In-game (F1 25 under CrossOver/Whisky): bind steer=X, throttle=Z, brake=Rz.
────────────────────────────────────────────────────────────────────────────
EOF
