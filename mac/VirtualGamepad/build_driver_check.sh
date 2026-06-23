#!/usr/bin/env bash
#
# Compile-checks the DriverKit extension sources (iig codegen + clang) without
# Xcode. This validates the C++/DriverKit code; it does NOT produce a loadable,
# signed .dext (that needs Xcode + your Apple Developer signing/entitlements).
#
set -euo pipefail
cd "$(dirname "$0")"

DK=$(xcrun --sdk driverkit --show-sdk-path)
IIG=$(xcrun --sdk driverkit --find iig)
CXX=$(xcrun --sdk driverkit --find clang++)
OUT=$(mktemp -d)
INC=(
  -I"$DK/System/DriverKit/System/Library/Frameworks/DriverKit.framework/Headers"
  -I"$DK/System/DriverKit/System/Library/Frameworks/HIDDriverKit.framework/Headers"
  -IShared -IDriver -I"$OUT"
)

echo "Generating iig sources…"
for base in VirtualGamepadDriver VirtualGamepadUserClient; do
    "$IIG" --def "Driver/$base.iig" --header "$OUT/$base.h" --impl "$OUT/$base.iig.cpp" -- \
        -x c++ -std=gnu++17 -D__IIG=1 -isysroot "$DK" "${INC[@]}"
done

echo "Compiling driver sources…"
for f in Driver/VirtualGamepadDriver.cpp Driver/VirtualGamepadUserClient.cpp \
         "$OUT/VirtualGamepadDriver.iig.cpp" "$OUT/VirtualGamepadUserClient.iig.cpp"; do
    "$CXX" -x c++ -std=gnu++17 -target arm64-apple-driverkit -isysroot "$DK" \
        -fno-exceptions -fno-rtti "${INC[@]}" -c "$f" -o "$OUT/$(basename "$f").o"
    echo "  ok: $(basename "$f")"
done

echo "✅ DriverKit sources compile cleanly."
