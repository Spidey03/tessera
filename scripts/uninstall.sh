#!/usr/bin/env bash
#
# Fully remove Tessera (both login agents, app bundle, logs).
#
# Thin wrapper over the shared scripts/tessera-uninstall.sh so repo and brew
# share one tested uninstall path.
#
# Usage: scripts/uninstall.sh [--purge]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec "$ROOT_DIR/scripts/tessera-uninstall.sh" "$@"