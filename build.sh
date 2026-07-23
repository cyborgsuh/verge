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

# Sign with the stable self-signed identity if present so macOS keeps the
# Accessibility grant across rebuilds/reboots/OS updates; ad-hoc otherwise.
if security find-identity -p codesigning 2>/dev/null | grep -q "Verge Dev"; then
    codesign --force --deep --sign "Verge Dev" "$APP"
    echo "Built $APP (signed: Verge Dev)"
else
    codesign --force --sign - "$APP" 2>/dev/null || true
    echo "Built $APP (ad-hoc — no 'Verge Dev' cert; grant will reset on rebuild)"
fi
