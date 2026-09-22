#!/usr/bin/env bash
#
# Assemble Tessera.app — a real macOS app bundle for the menu bar companion.
#
# Bundling the menu app (with the daemon inside) gives a stable bundle
# identifier, which is what TCC (System Settings privacy grants) honors for
# processes started by launchd at login — plain unsigned binaries are silently
# denied accessibility/input-monitoring grants when launchd is their ancestor.
#
# Layout:
#   Tessera.app/
#     Contents/Info.plist         (bundle id com.spidey.tessera, LSUIElement)
#     Contents/MacOS/TesseraMenu     menu bar app (bundle executable)
#     Contents/MacOS/TesseraDaemon   daemon spawned by the menu app
#
# Usage: scripts/build_app.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="Tessera"
VERSION="0.4.0"
BIN_DIR="$HOME/Library/Application Support/Tessera"
DEST="$BIN_DIR/$APP_NAME.app"
CONTENTS="$DEST/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> Building release binaries…"
(cd "$ROOT_DIR/TesseraKit" && swift build -c release)

echo "==> Assembling $APP_NAME.app"
rm -rf "$DEST"
mkdir -p "$MACOS"
cp "$ROOT_DIR/TesseraKit/.build/release/TesseraMenu" "$MACOS/TesseraMenu"
cp "$ROOT_DIR/TesseraKit/.build/release/TesseraDaemon" "$MACOS/TesseraDaemon"
chmod +x "$MACOS/TesseraMenu" "$MACOS/TesseraDaemon"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.spidey.tessera</string>
    <key>CFBundleName</key>
    <string>Tessera</string>
    <key>CFBundleDisplayName</key>
    <string>Tessera</string>
    <key>CFBundleExecutable</key>
    <string>TesseraMenu</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Spidey03. MIT License.</string>
</dict>
</plist>
PLIST

echo "==> Code signing"
IDENTITY="Tessera Plugin Identity"
if security find-identity -p codesigning -v 2>/dev/null | grep -q "$IDENTITY"; then
    # Local signing identity if present. (Note: it will NOT unlock TCC on
    # macOS 15+ — no Apple-issued TeamIdentifier — so the tiling daemon still
    # needs to ride a granted terminal's lineage once installed.)
    echo "   signing with '$IDENTITY'…"
    codesign --force --deep --sign "$IDENTITY" --timestamp=none "$DEST"
else
    echo "   signing ad-hoc…"
    codesign --force --deep --sign - --timestamp=none "$DEST" 2>/dev/null || true
fi

echo ""
echo "Tessera.app ready: $DEST"