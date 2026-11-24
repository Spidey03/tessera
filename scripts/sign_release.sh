#!/usr/bin/env bash
#
# Sign and publish the draft release built by .github/workflows/release.yml.
# Run on the maintainer's machine: the update key never goes to CI.
#
# Verifies that the update package and appcast were built by the release
# workflow from exactly the commit your LOCAL tag points at, signs the appcast,
# uploads the signature and publishes the draft.
#
# Usage: scripts/sign_release.sh <version> [--dry-run]   (e.g. 0.5.0)
#   --dry-run            verify and sign locally, upload/publish nothing
#   TESSERA_UPDATE_KEY   key file (default ~/TesseraSigning/tessera_update_ed25519.key)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
REPO="Spidey03/tessera"
VERSION="${1:?usage: scripts/sign_release.sh <version> [--dry-run]}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
KEY_FILE="${TESSERA_UPDATE_KEY:-$HOME/TesseraSigning/tessera_update_ed25519.key}"
[ -r "$KEY_FILE" ] || { echo "error: no update key at $KEY_FILE" >&2; exit 1; }
COMMIT="$(git rev-parse --verify "refs/tags/$TAG^{commit}")"

if [ "$(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft)" != true ]; then
    echo "error: $TAG is not a draft; refusing to change a published release" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ZIP="$WORK/tessera-$VERSION-dist.zip"
APPCAST="$WORK/appcast.json"
gh release download "$TAG" --repo "$REPO" --dir "$WORK" \
    --pattern "tessera-$VERSION-dist.zip" --pattern appcast.json

for file in "$ZIP" "$APPCAST"; do
    echo "==> Verifying build attestation: $(basename "$file")"
    gh attestation verify "$file" --repo "$REPO" \
        --signer-workflow "$REPO/.github/workflows/release.yml" \
        --source-ref "refs/tags/$TAG" --source-digest "$COMMIT" \
        --deny-self-hosted-runners
done

# expect <appcast key> <value>
expect() {
    local actual
    actual="$(plutil -extract "$1" raw -o - "$APPCAST")"
    [ "$actual" = "$2" ] || { echo "error: appcast $1 is '$actual', expected '$2'" >&2; exit 1; }
}
expect version "$VERSION"
expect sha256 "$(shasum -a 256 "$ZIP" | awk '{print $1}')"
expect size "$(stat -f%z "$ZIP")"

PUBLIC_KEY="$(git show "$COMMIT:TesseraKit/Sources/TesseraKit/Core/Update.swift" |
    sed -nE 's/.*publicKeyBase64 = "([^"]+)".*/\1/p')"
TESSERA_UPDATE_PRIVATE_KEY="$(cat "$KEY_FILE")" \
    swift scripts/sign_update.swift sign "$APPCAST" "$PUBLIC_KEY"
echo "==> Signed appcast for $TAG ($COMMIT)"

if [ "${2:-}" = --dry-run ]; then
    echo "Dry run: nothing uploaded or published."
    exit 0
fi
# Publish only after the signature is up, so clients never see an unsigned appcast.
gh release upload "$TAG" "$APPCAST.sig" --repo "$REPO" --clobber
gh release edit "$TAG" --repo "$REPO" --draft=false
