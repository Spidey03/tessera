class Tessera < Formula
  desc "BSP tiling window manager for macOS"
  homepage "https://github.com/Spidey03/tessera"
  url "https://github.com/Spidey03/tessera/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "f8b7b8a1107911845a40f17ec67ac3bf62338f6af39d8645bc077174678f2967"
  license "MIT"

  depends_on macos: :sonoma

  # NOTE: do NOT run `brew services start tessera`. macOS 15+ denies
  # Accessibility/Input Monitoring to launchd-spawned (unsigned) processes, so
  # the daemon is started THROUGH Terminal.app instead. Run `tessera-install`
  # once to wire up the login items.
  def install
    # Build release binaries and assemble Tessera.app into the staging dir.
    ENV["TESSERA_DEST"] = "#{buildpath}/Tessera.app"
    system "./scripts/build_app.sh"

    libexec.install "Tessera.app"
    bin.install "TesseraKit/.build/release/TesseraDaemon" => "tessera"
    bin.install "scripts/tessera-install.sh" => "tessera-install"
    bin.install "scripts/tessera-uninstall.sh" => "tessera-uninstall"
  end

  def caveats
    <<~EOS
      Wire up the login items (menu bar app + tiling daemon) once:

      brew services is NOT used here: on macOS 15+ a launchd-spawned process is
      denied Accessibility / Input Monitoring grants. Tessera starts the daemon
      through Terminal.app so it inherits your terminal's grants.

        1. System Settings → Privacy & Security → Accessibility and
           Input Monitoring: add your terminal (Terminal.app, etc.).
        2. Run:  tessera-install
        3. Check: tessera-install --check

      A Terminal window appears briefly at each login — that is the daemon
      being launched inside your granted terminal.

      Remove anytime with:  tessera-uninstall
      (keeps ~/.config/tessera; add --purge to remove it too)
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/tessera --version")
  end
end
