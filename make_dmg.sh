#!/bin/bash
# Package Verge.app into a styled drag-to-install DMG (branded background,
# icon layout, drag arrow). Needs Finder Automation permission for the
# AppleScript styling pass; the DMG still builds (unstyled) if that's denied.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

# Branded window background (@1x + @2x -> hidpi tiff).
BG_DIR="tools/dmg-bg"
BG_BUILD="$(mktemp -d)"
swiftc -O -o "$BG_BUILD/makedmgbg" tools/MakeDmgBackground.swift
"$BG_BUILD/makedmgbg" "$BG_DIR"
rm -rf "$BG_BUILD"

# Stage the volume contents.
STAGE="$(mktemp -d)/Verge"
mkdir -p "$STAGE/.background"
cp -R Verge.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target
tiffutil -cathidpicheck "$BG_DIR/background.png" "$BG_DIR/background@2x.png" \
    -out "$STAGE/.background/background.tiff"

VOL="/Volumes/Verge"
[ -d "$VOL" ] && hdiutil detach "$VOL" -force >/dev/null 2>&1 || true

rm -f Verge.temp.dmg Verge.dmg
hdiutil create -volname Verge -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ \
    -size 16m Verge.temp.dmg >/dev/null
rm -rf "$(dirname "$STAGE")"

hdiutil attach Verge.temp.dmg -readwrite -noverify -noautoopen >/dev/null
sleep 2

# Style the Finder window on the mounted volume. Non-fatal: an unstyled DMG
# still installs fine, so a denied Automation prompt shouldn't kill the build.
osascript <<'EOF' || echo "warning: Finder styling failed (Automation permission?) — DMG will be unstyled"
try
    tell application "Finder"
        tell disk "Verge"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 860, 560}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 120
            set label position of viewOptions to bottom
            set background picture of viewOptions to file ".background:background.tiff"
            delay 1
            set position of item "Verge.app" of container window to {170, 235}
            set position of item "Applications" of container window to {490, 235}
            update without registering applications
            delay 2
            close
        end tell
    end tell
end try
EOF

# Strip system cruft so it doesn't show in the window (keep .background + .DS_Store).
rm -rf "$VOL/.fseventsd" "$VOL/.Trashes" "$VOL/.DocumentRevisions-V100" \
       "$VOL/.Spotlight-V100" "$VOL/.TemporaryItems" 2>/dev/null || true
# Force the background dir invisible (hidden even with ⌘⇧. show-hidden on).
SetFile -a V "$VOL/.background" 2>/dev/null || chflags hidden "$VOL/.background" 2>/dev/null || true

sync
sleep 1
hdiutil detach "$VOL" >/dev/null || hdiutil detach "$VOL" -force >/dev/null

hdiutil convert Verge.temp.dmg -format UDZO -ov -o Verge.dmg >/dev/null
rm -f Verge.temp.dmg

echo "Built Verge.dmg ($(du -h Verge.dmg | cut -f1))"
