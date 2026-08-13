#!/bin/bash
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)

bash -n "$repo_root/bin/brew-watchtower"
output=$("$repo_root/bin/brew-watchtower" version)
[ "$output" = "brew-watchtower 0.1.0" ]
"$repo_root/bin/brew-watchtower" help | grep -q 'brew-watchtower add GROUP TYPE TOKEN'

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
HOME="$sandbox" "$repo_root/bin/brew-watchtower" config init >/dev/null
[ -f "$sandbox/.config/brew-watchtower/config" ]
grep -q '^blurb=actionable$' "$sandbox/.config/brew-watchtower/config"

state_dir="$sandbox/Library/Application Support/Homebrew AutoUpdate"
mkdir -p "$state_dir"
cat > "$state_dir/security.status" <<'EOF'
last_run=1786628428
result=success
pending_interactive=tailscale-app
brewfile_drift=detected
brewfile_export=disabled
EOF
blurb=$(HOME="$sandbox" "$repo_root/bin/brew-watchtower" blurb)
printf '%s\n' "$blurb" | grep -q '⛫ Watchtower: security: update tailscale-app; Brewfile drift detected'
printf 'blurb=never\n' > "$sandbox/.config/brew-watchtower/config"
[ -z "$(HOME="$sandbox" "$repo_root/bin/brew-watchtower" blurb)" ]

if command -v mandoc >/dev/null 2>&1; then
  mandoc -T lint "$repo_root/man/brew-watchtower.1"
fi

echo "All tests passed."
