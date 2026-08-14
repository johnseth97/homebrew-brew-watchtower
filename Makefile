VERSION ?= 0.1.0
PREFIX ?= $(HOME)/.local
DEV_ROOT := $(PREFIX)/libexec/brew-watchtower

.PHONY: test dist verify-release install uninstall clean

test:
	@bash tests/test.sh

dist: test
	@python3 scripts/build-release.py "$(VERSION)"

verify-release: dist
	@python3 scripts/verify-release.py "$(VERSION)"

# Install this checkout without touching Homebrew's managed prefix. The launcher
# in $(PREFIX)/bin points at an isolated runtime under $(DEV_ROOT).
install: test
	@test ! -e "$(PREFIX)/bin/brew-watchtower" || test -L "$(PREFIX)/bin/brew-watchtower" || { echo "refusing to replace non-symlink: $(PREFIX)/bin/brew-watchtower" >&2; exit 1; }
	@install -d "$(DEV_ROOT)/bin" "$(DEV_ROOT)/lib" "$(DEV_ROOT)/share/man/man1" "$(DEV_ROOT)/share/bash-completion/completions" "$(DEV_ROOT)/share/zsh/site-functions" "$(PREFIX)/bin"
	@install -m 0755 bin/brew-watchtower "$(DEV_ROOT)/bin/brew-watchtower"
	@install -m 0644 lib/*.sh "$(DEV_ROOT)/lib/"
	@install -m 0644 man/brew-watchtower.1 "$(DEV_ROOT)/share/man/man1/"
	@install -m 0644 completions/brew-watchtower.bash "$(DEV_ROOT)/share/bash-completion/completions/brew-watchtower"
	@install -m 0644 completions/_brew-watchtower "$(DEV_ROOT)/share/zsh/site-functions/_brew-watchtower"
	@ln -sfn "../libexec/brew-watchtower/bin/brew-watchtower" "$(PREFIX)/bin/brew-watchtower"
	@echo "Installed development build: $(PREFIX)/bin/brew-watchtower"

uninstall:
	@if test -L "$(PREFIX)/bin/brew-watchtower" && test "$$(readlink "$(PREFIX)/bin/brew-watchtower")" = "../libexec/brew-watchtower/bin/brew-watchtower"; then rm "$(PREFIX)/bin/brew-watchtower"; fi
	@rm -rf "$(DEV_ROOT)"
	@echo "Removed development build from $(PREFIX)"

clean:
	@rm -rf dist
