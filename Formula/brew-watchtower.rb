class BrewWatchtower < Formula
  desc "Grouped, scheduled Homebrew updates for macOS"
  homepage "https://github.com/johnseth97/homebrew-brew-watchtower"
  url "https://github.com/johnseth97/homebrew-brew-watchtower/releases/download/v0.1.0/brew-watchtower-0.1.0.tar.gz"
  sha256 "bc765d6aaaf6b2ffa4b5b192e2479a92df30cacd2c95ab18c5fbecc40d2f8d54"
  license "MIT"

  depends_on :macos

  def install
    bin.install "bin/brew-watchtower"
    man1.install "man/brew-watchtower.1"
    prefix.install "LICENSE"
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
    assert_match "brew-watchtower 0.1.0", shell_output("#{bin}/brew-watchtower version")
    assert_match "brew-watchtower add GROUP TYPE TOKEN", shell_output("#{bin}/brew-watchtower help")
  end
end
