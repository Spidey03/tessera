cask "tessera" do
  version "0.4.0"
  sha256 "9e6e305d3debf405a67f78952b468d3e2389e1f3797389adf047b473a8d79f6e"

  url "https://github.com/Spidey03/tessera/releases/download/v#{version}/tessera-#{version}.dmg"
  name "Tessera"
  desc "BSP tiling window manager (menu bar app + daemon)"
  homepage "https://github.com/Spidey03/tessera"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on :macos

  app "Tessera.app"

  uninstall quit: "com.spidey.tessera"

  caveats <<~EOS
    This release is unsigned (ad-hoc). On first launch Gatekeeper blocks it —
    right-click Tessera.app in /Applications and choose Open. When a signed +
    notarized DMG is released, this step disappears.

    Login items are NOT installed by the cask. Run:
      tessera-install --app /Applications/Tessera.app
    (if you don't have the Homebrew formula installed, use
      /Applications/Tessera.app/Contents/Resources/auth_start.zsh from a granted terminal).

    Verify with:
      tessera-install --check
  EOS
end
