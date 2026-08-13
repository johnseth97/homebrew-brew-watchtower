#!/bin/bash
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)

bash -n "$repo_root/bin/brew-watchtower"
output=$("$repo_root/bin/brew-watchtower" version)
[ "$output" = "brew-watchtower 0.1.0" ]
"$repo_root/bin/brew-watchtower" help | grep -q 'brew-watchtower add GROUP TYPE TOKEN'

if command -v mandoc >/dev/null 2>&1; then
  mandoc -T lint "$repo_root/man/brew-watchtower.1"
fi

echo "All tests passed."
