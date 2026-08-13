class BrewWatchtower < Formula
  desc "Grouped, scheduled Homebrew updates for macOS"
  homepage "https://github.com/johnseth97/homebrew-brew-watchtower"
  url "https://github.com/johnseth97/homebrew-brew-watchtower/releases/download/v0.2.1/brew-watchtower-0.2.1.tar.gz"
  sha256 "41a17f09806027c6d10e34c32c2ebc8cd10a11e1dc64259b0928c7a2ff2299da"
  license "MIT"

  depends_on :macos

  def install
    bin.install "bin/brew-watchtower"
    man1.install "man/brew-watchtower.1"
    lib.install Dir["lib/*.sh"]
    prefix.install "LICENSE"

  def post_install
    config_root = Pathname.new(Dir.home) / ".config"
    config_file = config_root / "brew-watchtower" / "config"
    system bin/"brew-watchtower", "config", "init" if config_root.directory? && !config_file.exist?
  end
  end

  def caveats
    <<~EOS
      Install the protected runtime and initial daily security schedule with:

        brew-watchtower setup

      Then add packages, for example:

        brew-watchtower add security cask tailscale-app interactive
    EOS
  end

  test do
    assert_match "brew-watchtower 0.2.1", shell_output("#{bin}/brew-watchtower version")
    assert_match "brew-watchtower add GROUP TYPE TOKEN", shell_output("#{bin}/brew-watchtower help")
  end
end
