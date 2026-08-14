VERSION ?= 0.1.0
PREFIX ?= $(HOME)/.local
DEV_NAME ?= brew-watchtower-dev
DEV_ROOT := $(PREFIX)/libexec/$(DEV_NAME)
DEV_BASH_COMPLETION_DIR := $(PREFIX)/share/bash-completion/completions
DEV_ZSH_COMPLETION_DIR := $(PREFIX)/share/zsh/site-functions

.PHONY: test dist verify-release install uninstall clean

test:
	@bash tests/test.sh

dist: test
	@python3 scripts/build-release.py "$(VERSION)"

verify-release: dist
	@python3 scripts/verify-release.py "$(VERSION)"

# Install this checkout without touching Homebrew's managed prefix. The launcher
# in $(PREFIX)/bin uses DEV_NAME and points at an isolated runtime under $(DEV_ROOT).
install: test
	@test ! -e "$(PREFIX)/bin/$(DEV_NAME)" || test -L "$(PREFIX)/bin/$(DEV_NAME)" || { echo "refusing to replace non-symlink: $(PREFIX)/bin/$(DEV_NAME)" >&2; exit 1; }
	@install -d "$(DEV_ROOT)/bin" "$(DEV_ROOT)/lib" "$(DEV_ROOT)/share/man/man1" "$(DEV_BASH_COMPLETION_DIR)" "$(DEV_ZSH_COMPLETION_DIR)" "$(PREFIX)/bin"
	@install -m 0755 bin/brew-watchtower "$(DEV_ROOT)/bin/$(DEV_NAME)"
	@install -m 0644 lib/*.sh "$(DEV_ROOT)/lib/"
	@sed 's/brew-watchtower/$(DEV_NAME)/g' man/brew-watchtower.1 > "$(DEV_ROOT)/share/man/man1/$(DEV_NAME).1"
	@sed 's/brew-watchtower/$(DEV_NAME)/g' completions/brew-watchtower.bash > "$(DEV_BASH_COMPLETION_DIR)/$(DEV_NAME)"
	@sed 's/brew-watchtower/$(DEV_NAME)/g' completions/_brew-watchtower > "$(DEV_ZSH_COMPLETION_DIR)/_$(DEV_NAME)"
	@ln -sfn "../libexec/$(DEV_NAME)/bin/$(DEV_NAME)" "$(PREFIX)/bin/$(DEV_NAME)"
	@echo "Installed development build: $(PREFIX)/bin/$(DEV_NAME)"

uninstall:
	@if test -L "$(PREFIX)/bin/$(DEV_NAME)" && test "$$(readlink "$(PREFIX)/bin/$(DEV_NAME)")" = "../libexec/$(DEV_NAME)/bin/$(DEV_NAME)"; then rm "$(PREFIX)/bin/$(DEV_NAME)"; fi
	@rm -f "$(DEV_BASH_COMPLETION_DIR)/$(DEV_NAME)" "$(DEV_ZSH_COMPLETION_DIR)/_$(DEV_NAME)"
	@rm -rf "$(DEV_ROOT)"
	@echo "Removed development build from $(PREFIX)"

clean:
	@rm -rf dist
