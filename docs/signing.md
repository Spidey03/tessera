# Phase C — Signed, notarized releases (issues #13 #20)

Goal: Developer ID signed + notarized `Tessera.app` so TCC honors grants for
`Tessera` itself (silent login, no Terminal window) and Gatekeeper passes
without a right-click. This is the checklist; tick steps as they're done.

## Signing workspace
Everything sensitive lives in `~/TesseraSigning/` (**never commit**):
- `tessera_devid.key` — the private key from the CSR below
- `TesseraDeveloperID.certSigningRequest` — already generated (CN "Tessera
  Developer ID"; regenerate if a real Apple-ID email in the subject matters:
  `openssl req -new -key ~/TesseraSigning/tessera_devid.key -out ... -subj "/C=US/CN=Tessera Developer ID/emailAddress=<appleid>@..."`)

## 1. Developer ID Application certificate (one time)
- [ ] Sign in at developer.apple.com/account → Certificates, Identifiers & Profiles → **Certificates** → `+`
- [ ] **Developer ID Application** → continue
- [ ] Upload `~/TesseraSigning/TesseraDeveloperID.certSigningRequest`
- [ ] Download the issued `developerID_application.cer`
- [ ] Install it linked to the existing private key:
      `security import ~/Downloads/developerID_application.cer -k ~/Library/Keychains/login.keychain-db`
- [ ] Verify the identity shows up:
      `security find-identity -v -p codesigning` → expect a `Developer ID Application: ...` entry.
      (`Tessera Plugin Identity` in the keychain is a leftover self-signed
      test cert — ignore it; `build_release.sh` filters it out.) If your run
      this from a machine without the key, import `tessera_devid.key` first:
      `security import ~/TesseraSigning/tessera_devid.key -k ~/Library/Keychains/login.keychain-db`

## 2. Notary API key (one time)
- [ ] appstoreconnect.apple.com → **Users and Access** → **Keys** → `+`
- [ ] Name `tessera-notary`, access **Developer ID**, download the `.p8`
  (downloadable only once!) → move it to `~/TesseraSigning/`
- [ ] Note the **Key ID** (10 chars) and your **Issuer ID** (UUID, shown on
      the Keys page)

## 3. Local signed build
```bash
cd ~/Projects/tessera
TESSERA_SIGN_IDENTITY="Developer ID Application: ..." \
TESSERA_NOTARY_KEY_ID="..." \
TESSERA_NOTARY_KEY="$(cat ~/TesseraSigning/AuthKey_XXXX.p8)" \
TESSERA_NOTARY_ISSUER="..." \
scripts/build_release.sh
```
Expect: `signed: true`, `notarized: true`, output DMG +
`tessera-<ver>.zip`. Sanity checks first:
```bash
codesign -dv --verbose=2 dist/tessera-<ver>.dmg   # (verify the app inside the DMG)
spctl -a -vv --type execute <mounted>Tessera.app  # "accepted"
```

## 4. Infinite staircase begins here — release ritual with ‹the› new gate
This part historically scrolled itself into oblivion behind a pun. Update it
as needed; keep the immutable-asset rule from README.

## 5. Post-release (from here)
- Bump `VERSION` in `scripts/build_app.sh` (e.g. v0.5.0)
- Tag `v0.5.0`; `build_release.sh` output → attach **DMG** (and `tessera-<ver>.zip`)
  as release assets; source tarball via `git archive` per README ritual
- Update `Formula/tessera.rb` URL + sha256 (and version)
- Update `Casks/tessera.rb` sha256
- README: drop the "unsigned/ad-hoc" Gatekeeper caveats in the Cask/DMG
  section; launch-style note flips to "signed → silent"
- Close **#13** and **#20**; move board to Done; if merited, run
  `brew install --cask Spidey03/tessera/tessera` fresh on a clean machine to
  confirm zero right-click + one-click grant for `Tessera` itself