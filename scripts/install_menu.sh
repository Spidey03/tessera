#!/usr/bin/env bash
#
# Install the Tessera menu bar companion as a login LaunchAgent.
#
# Builds Tessera.app (menu bar app + daemon bundled together, see
# scripts/build_app.sh), then delegates all login-item wiring to the shared
# scripts/tessera-install.sh.
#
# Usage: scripts/install_menu.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Building Tessera.app"
"$ROOT_DIR/scripts/build_app.sh"

exec "$ROOT_DIR/scripts/tessera-install.sh" --app "$HOME/Library/Application Support/Tessera/Tessera.app"