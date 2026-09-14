class Tessera < Formula
  desc "BSP tiling window manager for macOS"
  homepage "https://github.com/Spidey03/tessera"
  # TODO(release): fill sha256 after pushing the v0.4.0 tag:
  #   git tag v0.4.0 && git push origin v0.4.0
  #   curl -Ls https://github.com/Spidey03/tessera/archive/refs/tags/v0.4.0.tar.gz | shasum -a 256
  url "https://github.com/Spidey03/tessera/archive/refs/tags/v0.4.0.tar.gz"
  sha256 ""
  version "0.4.0"
  license "MIT"

  depends_on :macos => :sonoma

  def install
    cd("TesseraKit") do
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/TesseraDaemon" => "tessera"
    end
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/tessera --version")
  end
end