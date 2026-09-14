#!/usr/bin/env bash
#
# Install the Tessera menu bar companion as a login LaunchAgent.
#
# Builds a release TesseraMenu, copies it to a stable location, writes the
# LaunchAgent plist, and loads it so the menu item auto-starts on login.
#
# Usage: scripts/install_menu.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LABEL="com.tessera.menu"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN_DIR="$HOME/Library/Application Support/Tessera"
BIN_PATH="$BIN_DIR/TesseraMenu"

echo "==> Building release menu bar app…"
(cd "$ROOT_DIR/TesseraKit" && swift build -c release --product TesseraMenu)

echo "==> Installing binary to $BIN_PATH"
mkdir -p "$BIN_DIR"
cp "$ROOT_DIR/TesseraKit/.build/release/TesseraMenu" "$BIN_PATH"
chmod +x "$BIN_PATH"

# Unload existing agent (ignore failure if not loaded) so we can replace it.
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

echo "==> Writing LaunchAgent plist"
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$BIN_PATH</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <false/>

    <key>ProcessType</key>
    <string>Interactive</string>

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/Tessera/menu.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Tessera/menu.err.log</string>
</dict>
</plist>
PLIST

echo "==> Loading LaunchAgent"
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart "gui/$(id -u)/$LABEL"

echo ""
echo "Done. Tessera menu bar app installed as a login agent ($LABEL)."
echo "  Binary: $BIN_PATH"
echo "  Plist:  $PLIST_PATH"
echo "  Logs:   $HOME/Library/Logs/Tessera/menu.log"
echo ""
echo "Note: the daemon is managed separately via scripts/install_daemon.sh"
echo "Restart the menu agent with: launchctl kickstart -k gui/\$(id -u)/$LABEL"