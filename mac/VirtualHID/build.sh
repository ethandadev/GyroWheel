#!/usr/bin/env bash
#
# Builds the userspace virtual-gamepad CLI and signs it with the virtual-HID
# entitlement. See the two run modes printed at the end.
#
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling gyrohid…"
xcrun -sdk macosx swiftc -O -target arm64-apple-macos13.0 \
    -import-objc-header bridge.h main.swift \
    -framework IOKit -framework Network -o gyrohid

# Sign with the entitlement.
#   • Personal use (SIP/AMFI disabled): ad-hoc signature is fine.
#   • Distribution / SIP-on: set SIGN_ID="Developer ID Application: …" with a
#     provisioning profile that includes com.apple.developer.hid.virtual.device.
SIGN_ID="${SIGN_ID:--}"
echo "Signing with identity: ${SIGN_ID}"
codesign --force --sign "${SIGN_ID}" --entitlements VirtualHID.entitlements gyrohid

echo "✅ Built ./gyrohid"
cat <<'EOF'

────────────────────────────────────────────────────────────────────────────
 RUN — pick one mode:

 A) Personal use, no Apple approval (your research path)
    One-time, in macOS Recovery (boot: hold power on Apple Silicon → Options):
        csrutil disable
        # append to existing boot-args; don't overwrite:
        nvram boot-args="amfi_get_out_of_my_way=1"
    Reboot, then:
        sudo ./gyrohid
    Re-enable later with `csrutil enable` + clearing boot-args in Recovery.
    ⚠️  This lowers system security machine-wide — only do it knowingly.

 B) Paid account with the granted entitlement (no SIP changes)
    Request com.apple.developer.hid.virtual.device for your account, then:
        SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
        ./gyrohid          # sudo not required once the entitlement is honored

 Then: on the phone, point it at this Mac's IP + port 5005. Verify the pad in
 any gamepad tester; in F1 25 bind steer→X, throttle→Z, brake→Rz.
────────────────────────────────────────────────────────────────────────────
EOF
