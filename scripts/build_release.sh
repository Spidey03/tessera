#!/usr/bin/env bash
#
# Build a signed + notarized release artifact for Tessera: Tessera.app (from
# scripts/build_app.sh), optional Developer ID signing, optional notarization +
# stapling, and a distributable DMG.
#
# Everything is credential-conditional so the pipeline runs (and is fully
# exercisable) even without an Apple Developer account:
#   - no Developer ID identity  -> ad-hoc signing, loud "UNSIGNED" warning
#   - no notary credentials     -> notarization skipped, loud warning
#
# Usage:
#   TESSERA_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   TESSERA_NOTARY_KEY_ID=... TESSERA_NOTARY_KEY=... TESSERA_NOTARY_ISSUER=... \
#   scripts/build_release.sh [--out dist]
#
# Env:
#   TESSERA_SIGN_IDENTITY   codesign identity; default: first "Developer ID
#                           Application" found in the keychain, else ad-hoc.
#   TESSERA_NOTARY_*        notarytool API-key credentials (key id, key PEM,
#                           issuer id). Alternatively TESSERA_APPLE_ID +
#                           TESSERA_APPLE_PASSWORD + TESSERA_TEAM_ID.
#   TESSERA_DEST            staging dir for the build (default: mktemp)
#   TESSERA_OUT_DIR         output dir for artifacts (default: ./dist)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$ROOT_DIR/scripts/build_app.sh")"

OUT_DIR="${TESSERA_OUT_DIR:-$ROOT_DIR/dist}"
[ "${1:-}" = "--out" ] && { OUT_DIR="$2"; shift 2; }
STAGE="${TESSERA_DEST:-$(mktemp -d)/Tessera.app}"
mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/tessera-$VERSION.dmg"
ZIP="$OUT_DIR/tessera-$VERSION.zip"

echo "==> Tessera release build v$VERSION"

# --- 1. Build the app bundle ---------------------------------------------
TESSERA_DEST="$STAGE" "$ROOT_DIR/scripts/build_app.sh" >/dev/null
APP="$STAGE"
[ -x "$APP/Contents/MacOS/TesseraDaemon" ] || { echo "error: daemon not in bundle" >&2; exit 1; }

# --- 2. Sign --------------------------------------------------------------
SIGN_IDENTITY="${TESSERA_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | rg -m1 "Developer ID Application" | sed 's/.*"\(.*\)".*/\1/' || true)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing with '$SIGN_IDENTITY' (hardened runtime, timestamp)"
    codesign --force --deep --options runtime --timestamp \
             --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null
    echo "   signature verified ✓  (authority: $(codesign -dv "$APP" 2>&1 | rg 'Authority=Developer ID' | head -1))"
    SIGNED=true
else
    echo "==> Signing ad-hoc (NO Developer ID identity found)"
    echo "   !! UNSIGNED artifact — Gatekeeper will block/require right-click"
    echo "   !! Set TESSERA_SIGN_IDENTITY or install a Developer ID certificate."
    SIGNED=false
    [ -x "$APP/Contents/MacOS/TesseraMenu" ] && codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

# --- 3. Notarize + staple (only when signed AND credentials present) ------
NOTARIZED=false
if [ "$SIGNED" = true ]; then
    NOTARY_ARGS=()
    if [ -n "${TESSERA_NOTARY_KEY_ID:-}" ] && [ -n "${TESSERA_NOTARY_KEY:-}" ] && [ -n "${TESSERA_NOTARY_ISSUER:-}" ]; then
        NOTARY_ARGS=(--key-id "$TESSERA_NOTARY_KEY_ID" --key "$TESSERA_NOTARY_KEY" --issuer "$TESSERA_NOTARY_ISSUER")
    elif [ -n "${TESSERA_APPLE_ID:-}" ] && [ -n "${TESSERA_APPLE_PASSWORD:-}" ]; then
        NOTARY_ARGS=(--apple-id "$TESSERA_APPLE_ID" --password "$TESSERA_APPLE_PASSWORD" --team-id "${TESSERA_TEAM_ID:-}")
    fi

    if [ ${#NOTARY_ARGS[@]} -gt 0 ]; then
        echo "==> Notarizing…"
        ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
        xcrun notarytool submit "$ZIP" "${NOTARY_ARGS[@]}" --wait
        echo "==> Stapling…"
        xcrun stapler staple "$APP"
        spctl -a -vv --type execute "$APP" 2>&1 | rg "accepted|rejected" | head -2
        NOTARIZED=true
    else
        echo "==> Notarization SKIPPED"
        echo "   !! Set TESSERA_NOTARY_KEY_ID/KEY/ISSUER (or APPLE_ID/PASSWORD/TEAM_ID)."
    fi
fi

# --- 4. DMG -----------------------------------------------------------------
echo "==> Building DMG"
DMG_STAGE="$(mktemp -d)/Tessera"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Tessera $VERSION" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG" >/dev/null

# --- 5. Summary ---------------------------------------------------------------
echo ""
echo "=================  RELEASE ARTIFACTS  ================="
echo "  DMG : $DMG"
[ "$SIGNED" = true ] && [ "$NOTARIZED" = true ] && echo "  ZIP : $ZIP"
echo "  signed    : $SIGNED   ($([ "$SIGNED" = true ] && echo "$SIGN_IDENTITY" || echo 'ad-hoc — NOT distributable'))"
echo "  notarized : $NOTARIZED"
[ "$SIGNED" = true ] && [ "$NOTARIZED" = false ] && echo "  !! build is signed but NOT notarized — Gatekeeper will warn."
echo "======================================================="