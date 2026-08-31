#!/usr/bin/env bash
#
# Uninstall the Tessera LaunchAgent: unloads the agent, removes the plist,
# and deletes the installed binary.
#
# Usage: scripts/uninstall_daemon.sh
set -euo pipefail

LABEL="com.tessera.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN_DIR="$HOME/Library/Application Support/Tessera"

echo "==> Unloading LaunchAgent"
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

if [ -f "$PLIST_PATH" ]; then
    echo "==> Removing $PLIST_PATH"
    rm "$PLIST_PATH"
fi

if [ -d "$BIN_DIR" ]; then
    echo "==> Removing $BIN_DIR"
    rm -rf "$BIN_DIR"
fi

echo "Done. Tessera agent removed."
