#!/usr/bin/env bash
#
# Remove the Tessera menu bar companion LaunchAgent and its installed binary.
#
# Usage: scripts/uninstall_menu.sh
set -euo pipefail

LABEL="com.tessera.menu"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN_PATH="$HOME/Library/Application Support/Tessera/TesseraMenu"

echo "==> Unloading LaunchAgent"
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

echo "==> Removing plist and binary"
rm -f "$PLIST_PATH"
rm -f "$BIN_PATH"

echo "Done. Menu bar app removed."
echo "Note: to also remove the daemon, run scripts/uninstall_daemon.sh"