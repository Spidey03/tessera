#!/usr/bin/env bash
#
# Install the Tessera menu bar companion as a login LaunchAgent.
#
# Builds Tessera.app (menu bar app + daemon bundled together, see
# scripts/build_app.sh), points a LaunchAgent at the app's executable, and
# loads it so everything auto-starts on login.
#
# Usage: scripts/install_menu.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LABEL="com.tessera.menu"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN_DIR="$HOME/Library/Application Support/Tessera"
APP_PATH="$BIN_DIR/Tessera.app"
MENU_BIN="$APP_PATH/Contents/MacOS/TesseraMenu"

echo "==> Building Tessera.app"
"$ROOT_DIR/scripts/build_app.sh"

# Stop any existing menu/daemon so only the freshly-installed .app runs
# (guards against duplicate menu-bar icons and stale daemons).
pkill -f "TesseraDaemon" 2>/dev/null || true
pkill -f "TesseraMenu" 2>/dev/null || true

# Unload existing agent (ignore failure if not loaded) so we can replace it.
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

echo "==> Writing LaunchAgent plist ($LABEL)"
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-n</string>
        <string>$APP_PATH</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <false/>

    <key>ProcessType</key>
    <string>Interactive</string>

    <key>StandardOutPath</key>
    <string>$BIN_DIR/menu.log</string>

    <key>StandardErrorPath</key>
    <string>$BIN_DIR/menu.err.log</string>
</dict>
</plist>
PLIST

echo "==> Loading LaunchAgent"
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart "gui/$(id -u)/$LABEL"

# The tiling daemon can't be a launchd child (macOS 15+ refuses privacy grants
# to any process without an Apple-issued signing identity, so launchd-spawned —
# even via the .app — is always permission-less). Its lineage must reach a
# GRANTED GUI app. We start it through Terminal.app, which holds the grants.
TILING_LABEL="com.tessera.tiling"
TILING_PLIST="$HOME/Library/LaunchAgents/$TILING_LABEL.plist"
SCRIPT="$ROOT_DIR/scripts/auth_start.zsh"

echo "==> Writing tiling LaunchAgent ($TILING_LABEL)"
cat > "$TILING_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$TILING_LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>Terminal</string>
        <string>$SCRIPT</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <false/>

    <key>ProcessType</key>
    <string>Interactive</string>

    <key>StandardOutPath</key>
    <string>$BIN_DIR/tiling.log</string>

    <key>StandardErrorPath</key>
    <string>$BIN_DIR/tiling.err.log</string>
</dict>
</plist>
PLIST

echo "==> Loading tiling LaunchAgent"
launchctl bootout "gui/$(id -u)/$TILING_LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$TILING_PLIST"

echo ""
echo "Done. Tessera menu bar app installed as a login agent ($LABEL)."
echo "  App:      $APP_PATH"
echo "  Plist:    $PLIST_PATH"
echo ""
echo "The tiling daemon starts at login THROUGH Terminal.app (agent $TILING_LABEL),"
echo "because macOS only honors Accessibility/Input Monitoring grants for processes"
echo "born under a granted app — launchd children are always denied, regardless of"
echo "System Settings toggles."
echo ""
echo "Grant permissions ONCE in System Settings → Privacy & Security:"
echo "  Accessibility and Input Monitoring → add Terminal.app (or your terminal)."
echo "  (The daemon inherits your terminal's grant; 'Tessera' itself can't be granted.)"
echo "Restart the menu agent with: launchctl kickstart -k gui/\$(id -u)/$LABEL"