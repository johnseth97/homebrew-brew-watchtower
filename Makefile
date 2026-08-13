VERSION ?= 0.1.0

.PHONY: test dist verify-release clean

test:
	@bash tests/test.sh

dist: test
	@python3 scripts/build-release.py "$(VERSION)"

verify-release: dist
	@python3 scripts/verify-release.py "$(VERSION)"

clean:
	@rm -rf dist
