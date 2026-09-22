#!/usr/bin/env bash
#
# Fully remove Tessera: both login agents (com.tessera.menu,
# com.tessera.tiling), the installed app bundle + daemon launcher, and logs.
#
# Stops any running daemon and menu bar app along the way.
# Keeps ~/.config/tessera (your settings) unless --purge is passed.
#
# This is the single source of truth for uninstall wiring — used by the repo
# (scripts/uninstall.sh) and, via `brew install`, by the Homebrew formula.
#
# Usage: tessera-uninstall [--purge]
set -euo pipefail

PURGE=false
[ "${1:-}" = "--purge" ] && PURGE=true

UID_N="$(id -u)"
BIN_DIR="$HOME/Library/Application Support/Tessera"
LOG_DIR="$HOME/Library/Logs/Tessera"
CONFIG_DIR="$HOME/.config/tessera"

echo "==> Stopping daemon"
PIDFILE="$BIN_DIR/daemon.pid"
if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
fi
pkill -f "TesseraDaemon" 2>/dev/null || true

echo "==> Stopping menu bar app"
pkill -f "TesseraMenu" 2>/dev/null || true

for LABEL in com.tessera.menu com.tessera.tiling; do
    echo "==> Unloading $LABEL"
    launchctl bootout "gui/$UID_N/$LABEL" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
done

echo "==> Removing app bundle, launcher and pid/data"
rm -rf "$BIN_DIR"

echo "==> Removing logs"
rm -rf "$LOG_DIR"

if $PURGE; then
    echo "==> Removing config"
    rm -rf "$CONFIG_DIR"
else
    echo "Kept config: $CONFIG_DIR (pass --purge to remove it)"
fi

echo "Done. Tessera fully removed."