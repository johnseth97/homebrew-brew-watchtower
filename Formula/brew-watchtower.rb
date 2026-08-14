class BrewWatchtower < Formula
  desc "Grouped, scheduled Homebrew updates for macOS"
  homepage "https://github.com/johnseth97/homebrew-brew-watchtower"
  url "https://github.com/johnseth97/homebrew-brew-watchtower/releases/download/v0.9.0/brew-watchtower-0.9.0.tar.gz"
  sha256 "338a6469b96737f784d75fa79c86b7b857ba81ef3637a4601268a155a0e02f74"
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
    assert_match "brew-watchtower 0.9.0", shell_output("#{bin}/brew-watchtower version")
    assert_match "brew-watchtower add GROUP TYPE TOKEN", shell_output("#{bin}/brew-watchtower help")
  end
end
