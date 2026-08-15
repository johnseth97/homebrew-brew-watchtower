class BrewWatchtower < Formula
  desc "Grouped, scheduled Homebrew updates for macOS"
  homepage "https://github.com/johnseth97/homebrew-brew-watchtower"
  url "https://github.com/johnseth97/homebrew-brew-watchtower/releases/download/v0.10.1/brew-watchtower-0.10.1.tar.gz"
  sha256 "881c9c49a1ea6ec70169a50cde74f21310cd3e4e2d915fb865b9d2fa12855f2c"
  license "MIT"

  depends_on :macos

  def install
    bin.install "bin/brew-watchtower"
    bash_completion.install "completions/brew-watchtower.bash" => "brew-watchtower"
    zsh_completion.install "completions/_brew-watchtower"
    man1.install "man/brew-watchtower.1"
    lib.install Dir["lib/*.sh"]
    prefix.install "LICENSE"
  end

  def post_install
    config_root = Pathname.new(Dir.home) / ".config"
    config_file = config_root / "brew-watchtower" / "config"
    system bin/"brew-watchtower", "config", "init" if config_root.directory? && !config_file.exist?
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
    assert_match "brew-watchtower 0.10.1", shell_output("#{bin}/brew-watchtower version")
    assert_match "brew-watchtower add GROUP TYPE TOKEN", shell_output("#{bin}/brew-watchtower help")
  end
end
