#!/bin/bash
# Build Verge.app with swiftc (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

APP="Verge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O \
    -import-objc-header Sources/bridge.h \
    -F /System/Library/PrivateFrameworks \
    -framework MultitouchSupport \
    -framework MediaRemote \
    -framework DisplayServices \
    -framework CoreAudio \
    -framework Cocoa \
    -o "$APP/Contents/MacOS/Verge" \
    Sources/*.swift

# app icon: compile the generator and produce Verge.icns (runs iconutil itself)
mkdir -p "$APP/Contents/Resources"
ICON_BUILD="$(mktemp -d)"
swiftc -O -o "$ICON_BUILD/makeicon" tools/MakeIcon.swift
"$ICON_BUILD/makeicon" "$APP/Contents/Resources/Verge.icns"
rm -rf "$ICON_BUILD"

# ad-hoc sign so TCC (Accessibility) can pin a stable identity
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
