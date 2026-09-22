#!/usr/bin/env bash
#
# Install Tessera as login items: the menu bar app (com.tessera.menu) and the
# tiling daemon (com.tessera.tiling).
#
# The tiling daemon CANNOT be a plain launchd child on macOS 15+ — privacy
# grants (Accessibility / Input Monitoring) are only honored for processes born
# under a GUI app that holds them. So the tiling agent starts a Terminal window
# once via /usr/bin/open and runs scripts/auth_start.zsh inside it, making the
# daemon a descendant of the granted terminal.
#
# This is the single source of truth for install wiring — used by the repo
# (scripts/install_menu.sh) and, via `brew install`, by the Homebrew formula.
#
# Usage:
#   tessera-install            install/reinstall (idempotent)
#   tessera-install --check    verify the running install
#   tessera-install --help
#
# Options:
#   --app <path>   App bundle to install (default: App Support, then Cellar)
#   -h, --help     Show help
set -euo pipefail

LABEL_MENU="com.tessera.menu"
LABEL_TILING="com.tessera.tiling"
UID_N="$(id -u)"
BIN_DIR="$HOME/Library/Application Support/Tessera"
LOG_DIR="$HOME/Library/Logs/Tessera"
LOG_DAEMON="$LOG_DIR/daemon.log"

usage() {
    cat <<'EOF'
Usage:
  tessera-install [--app <path>]          install/reinstall (idempotent)
  tessera-install --check                 verify the running install
  tessera-install -h, --help              show this help

Locates Tessera.app (--app, then ~/Library/Application Support/Tessera, then
the Homebrew Cellar), copies it into place, writes both LaunchAgent plists
(com.tessera.menu, com.tessera.tiling), loads them, and prints the one-time
Accessibility/Input Monitoring grant steps for your terminal.
EOF
    exit 0
}

APP="${TESSERA_APP:-}"
CHECK=false
while [ $# -gt 0 ]; do
    case "$1" in
        --app)        shift; APP="$1" ;;
        --check)      CHECK=true ;;
        -h|--help)    usage ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

resolve_app() {
    local candidate
    for candidate in \
        "$APP" \
        "$BIN_DIR/Tessera.app" \
        "$(command -v brew >/dev/null && brew --prefix tessera 2>/dev/null || true)/libexec/Tessera.app"
    do
        [ -n "$candidate" ] || continue
        [ -x "$candidate/Contents/MacOS/TesseraMenu" ] || continue
        echo "$candidate"
        return 0
    done
    echo "error: cannot find Tessera.app" >&2
    echo "  Try: --app <path>, or install via 'brew install Spidey03/tessera/tessera'." >&2
    exit 1
}

check() {
    local ok=0 pid=""
    echo "==> Tessera health check"
    if [ -f "$BIN_DIR/daemon.pid" ]; then
        pid="$(cat "$BIN_DIR/daemon.pid" 2>/dev/null || true)"
    fi
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        echo "   [ok] daemon running (pid $pid)"
    elif pgrep -f "Tessera.app/Contents/MacOS/TesseraDaemon" >/dev/null; then
        echo "   [ok] daemon running ($(pgrep -f 'Tessera.app/Contents/MacOS/TesseraDaemon' | head -1))"
    else
        echo "   [!!] daemon NOT running" >&2; ok=1
    fi
    if pgrep -f "Tessera.app/Contents/MacOS/TesseraMenu" >/dev/null; then
        echo "   [ok] menu bar app running"
    else
        echo "   [!!] menu bar app NOT running" >&2; ok=1
    fi
    if launchctl print "gui/$UID_N/$LABEL_MENU" >/dev/null 2>&1; then
        echo "   [ok] agent $LABEL_MENU loaded"
    else
        echo "   [!!] agent $LABEL_MENU NOT loaded" >&2; ok=1
    fi
    if launchctl print "gui/$UID_N/$LABEL_TILING" >/dev/null 2>&1; then
        echo "   [ok] agent $LABEL_TILING loaded"
    else
        echo "   [!!] agent $LABEL_TILING NOT loaded" >&2; ok=1
    fi
    if [ -f "$LOG_DAEMON" ] && rg -q "AX trusted: true" "$LOG_DAEMON"; then
        echo "   [ok] daemon holds Accessibility grants"
    else
        echo "   [!!] Accessibility grant not detected — grant Terminal in" >&2
        echo "       System Settings → Privacy & Security → Accessibility / Input Monitoring" >&2
        ok=1
    fi
    echo ""
    [ "$ok" = 0 ] && echo "All good." || { echo "Fix the items above, then reinstall."; }
    return "$ok"
}

install() {
    APP="$(resolve_app)"
    local script_src="$APP/Contents/Resources/auth_start.zsh"

    echo "==> Installing $APP (login items)"
    echo "==> Stopping running daemon / menu"
    pkill -f "TesseraDaemon" 2>/dev/null || true
    pkill -f "TesseraMenu" 2>/dev/null || true

    for label in "$LABEL_MENU" "$LABEL_TILING"; do
        launchctl bootout "gui/$UID_N/$label" >/dev/null 2>&1 || true
    done

    echo "==> Installing app bundle + launcher to $BIN_DIR"
    mkdir -p "$BIN_DIR"
    [ ! -x "$script_src" ] && { echo "error: $script_src missing" >&2; exit 1; }
    rm -rf "$BIN_DIR/Tessera.app"
    cp -R "$APP" "$BIN_DIR/Tessera.app"
    chmod +x "$BIN_DIR/Tessera.app/Contents/MacOS/TesseraMenu" \
             "$BIN_DIR/Tessera.app/Contents/MacOS/TesseraDaemon"
    cp "$script_src" "$BIN_DIR/auth_start.zsh"
    chmod +x "$BIN_DIR/auth_start.zsh"

    echo "==> Writing LaunchAgent plists"
    cat > "$HOME/Library/LaunchAgents/$LABEL_MENU.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL_MENU</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-n</string>
        <string>$BIN_DIR/Tessera.app</string>
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
    cat > "$HOME/Library/LaunchAgents/$LABEL_TILING.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL_TILING</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>Terminal</string>
        <string>$BIN_DIR/auth_start.zsh</string>
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

    echo "==> Loading LaunchAgents"
    launchctl bootstrap "gui/$UID_N" "$HOME/Library/LaunchAgents/$LABEL_MENU.plist"
    launchctl kickstart "gui/$UID_N/$LABEL_MENU"
    launchctl bootstrap "gui/$UID_N" "$HOME/Library/LaunchAgents/$LABEL_TILING.plist"

    echo ""
    echo "Done. Tessera installed as login items."
    echo "  App: $BIN_DIR/Tessera.app"
    echo ""
    echo "Grant permissions ONCE in System Settings → Privacy & Security:"
    echo "  Accessibility and Input Monitoring → add Terminal.app (or your terminal)."
    echo "  The daemon inherits your terminal's grant; 'Tessera' itself can't be"
    echo "  granted because it is not Apple-signed (no TeamIdentifier)."
    echo ""
    echo "A Terminal window appears briefly at login to launch the daemon."
    echo "Verify everything with:  tessera-install --check"
}

if [ "$CHECK" = true ]; then
    check
else
    install
fi