#!/usr/bin/env bash
#
# Fail if any copy of the release version disagrees with the root VERSION file
# (the single source of truth). Copies that cannot read VERSION at build time
# (Swift constants, the Homebrew formula and cask) are checked here.
#
# Usage: scripts/check_version.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

expected="$(tr -d '[:space:]' < VERSION)"
if ! [[ "$expected" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must be MAJOR.MINOR.PATCH, got: '$expected'" >&2
    exit 1
fi

failures=0

# check <label> <actual>
check() {
    if [ "$2" != "$expected" ]; then
        echo "MISMATCH $1: '$2' (expected '$expected' from VERSION)" >&2
        failures=$((failures + 1))
    else
        echo "ok       $1: $2"
    fi
}

# extract <file> <ERE with one capture group>: first match, or empty.
extract() {
    sed -nE "s|$2|\1|p" "$1" | head -n 1
}

check "daemon  TesseraKit/Sources/TesseraDaemon/main.swift" \
    "$(extract TesseraKit/Sources/TesseraDaemon/main.swift '^let version = "([^"]*)"')"
check "menu    TesseraKit/Sources/TesseraMenu/main.swift" \
    "$(extract TesseraKit/Sources/TesseraMenu/main.swift '^let tesseraMenuVersion = "([^"]*)"')"
check "formula Formula/tessera.rb" \
    "$(extract Formula/tessera.rb '^[[:space:]]*version "([^"]*)"')"
check "cask    Casks/tessera.rb" \
    "$(extract Casks/tessera.rb '^[[:space:]]*version "([^"]*)"')"

# The formula's URL pins the release tag; it must point at the same version.
formula_url="$(extract Formula/tessera.rb '^[[:space:]]*url "([^"]*)"')"
if [[ "$formula_url" != *"/download/v$expected/tessera-$expected.tar.gz" ]]; then
    echo "MISMATCH formula url: '$formula_url' does not pin v$expected" >&2
    failures=$((failures + 1))
else
    echo "ok       formula url pins v$expected"
fi

if [ "$failures" -ne 0 ]; then
    echo "Version check failed: $failures mismatch(es). Fix the copies to match VERSION." >&2
    exit 1
fi
echo "Version check passed: $expected"
