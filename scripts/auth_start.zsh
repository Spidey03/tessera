#!/bin/zsh
#
# Start the Tessera tiling daemon from a GRANTED parent.
#
# macOS 15+ only honors Accessibility / Input Monitoring grants for processes
# whose signing identity carries a real TeamIdentifier (i.e. an Apple-issued
# certificate). Locally signed binaries can never satisfy that, and every
# launchd-spawned process (agent, app bundle, LaunchServices child) is denied —
# no matter which grants are toggled in System Settings.
#
# The one reliable path on macOS 26: birth the daemon as a descendant of a GUI
# app that DOES hold a grant — your terminal (Terminal.app / kitty). This script
# is harmless to run from anywhere; it is primarily run at login by the
# com.tessera.tiling LaunchAgent via `/usr/bin/open -a Terminal`.
#
# Usage: scripts/auth_start.zsh
set -euo pipefail

DAEMON="$HOME/Library/Application Support/Tessera/Tessera.app/Contents/MacOS/TesseraDaemon"
LOG="$HOME/Library/Logs/Tessera/daemon.log"
ERR="$HOME/Library/Logs/Tessera/daemon.err.log"
PIDFILE="$HOME/Library/Application Support/Tessera/daemon.pid"

if [ ! -x "$DAEMON" ]; then
    echo "Tessera daemon not found: $DAEMON" >&2
    exit 1
fi

# Already running? (pidfile + live process)
if [ -r "$PIDFILE" ]; then
    OLD_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        exit 0
    fi
fi

mkdir -p "$HOME/Library/Logs/Tessera"
nohup "$DAEMON" >>"$LOG" 2>>"$ERR" &
echo "Started Tessera tiling daemon (child of: $PPID)."
exit 0