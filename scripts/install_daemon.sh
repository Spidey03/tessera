#!/usr/bin/env bash
#
# Install the Tessera daemon binary.
#
# Builds a release binary, copies it to a stable location, and ad-hoc code
# signs it (stable TCC identity). The daemon is NOT a LaunchAgent: it is
# spawned by the menu bar app (menu) so it inherits the menu app's
# accessibility/input-monitoring trust.
#
# Usage: scripts/install_daemon.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LABEL="com.tessera.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN_DIR="$HOME/Library/Application Support/Tessera"
BIN_PATH="$BIN_DIR/TesseraDaemon"

echo "==> Building release daemon…"
(cd "$ROOT_DIR/TesseraKit" && swift build -c release --product TesseraDaemon)

echo "==> Installing binary to $BIN_PATH"
mkdir -p "$BIN_DIR"
cp "$ROOT_DIR/TesseraKit/.build/release/TesseraDaemon" "$BIN_PATH"
chmod +x "$BIN_PATH"
codesign --force --sign - --timestamp=none "$BIN_PATH" 2>/dev/null || true

# Clean up the old daemon LaunchAgent if present (pre-menu-management design).
if [ -f "$PLIST_PATH" ]; then
    echo "==> Removing old daemon LaunchAgent (menu app now manages the daemon)"
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    rm -f "$PLIST_PATH"
fi

echo ""
echo "Done. Tessera daemon installed."
echo "  Binary: $BIN_PATH"
echo "  Logs:   $HOME/Library/Logs/Tessera/daemon.log"
echo ""
echo "The daemon is spawned automatically by the menu bar app (menu), which"
echo "keeps it inside the accessibility/input-monitoring trust chain."
