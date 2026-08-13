#!/bin/bash
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)

bash -n "$repo_root/bin/brew-watchtower" "$repo_root"/lib/*.sh
output=$("$repo_root/bin/brew-watchtower" version)
[ "$output" = "brew-watchtower 0.4.0" ]
"$repo_root/bin/brew-watchtower" help | grep -q 'brew-watchtower add GROUP TYPE TOKEN'
"$repo_root/bin/brew-watchtower" help | grep -q 'brew-watchtower drift'
for completion in completions/brew-watchtower.bash completions/_brew-watchtower; do
  [ -f "$repo_root/$completion" ]
done
for module in policy runtime scheduler updates; do
  [ -f "$repo_root/lib/$module.sh" ]
done

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
HOME="$sandbox" "$repo_root/bin/brew-watchtower" config init >/dev/null
[ -f "$sandbox/.config/brew-watchtower/config" ]
grep -q '^blurb=actionable$' "$sandbox/.config/brew-watchtower/config"
config_path=$(HOME="$sandbox" "$repo_root/bin/brew-watchtower" config path)
[ "$config_path" = "$sandbox/.config/brew-watchtower/config" ]
config_show=$(HOME="$sandbox" "$repo_root/bin/brew-watchtower" config show)
printf '%s\n' "$config_show" | grep -q '^blurb=actionable$'
printf '%s\n' "$config_show" | grep -q '^detect_brewfile_drift=1$'

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

fake_brew="$sandbox/fake-brew"
cat > "$fake_brew" <<'EOF'
#!/bin/bash
set -eu
if [ "$1" = bundle ] && [ "$2" = dump ]; then
  shift 2
  while [ $# -gt 0 ]; do
    if [ "$1" = --file ]; then
      printf '# generated\nbrew "new-package"\n' > "$2"
      exit 0
    fi
    shift
  done
fi
if [ "$1" = bundle ] && [ "$2" = check ]; then
  exit 1
fi
exit 1
EOF
chmod 700 "$fake_brew"
mkdir -p "$sandbox/curated"
printf '# curated\nbrew "old-package"\n' > "$sandbox/curated/Brewfile"
cat > "$sandbox/.config/brew-watchtower/config" <<EOF
blurb=never
detect_brewfile_drift=1
brewfile=$sandbox/curated/Brewfile
export_brewfile=0
EOF
HOME="$sandbox" TEST_BREW="$fake_brew" REPO_ROOT="$repo_root" bash -c '
  set -eu
  PROGRAM=brew-watchtower
  BREW="$TEST_BREW"
  USER_HOME="$HOME"
  STATE_DIR="$HOME/Library/Application Support/Homebrew AutoUpdate"
  LOG_DIR="$HOME/Library/Logs/Homebrew AutoUpdate"
  CACHE_DIR="$HOME/Library/Caches/Homebrew AutoUpdate"
  CONFIG_DIR="$HOME/.config/brew-watchtower"
  CONFIG_FILE="$CONFIG_DIR/config"
  source "$REPO_ROOT/lib/runtime.sh"
  source "$REPO_ROOT/lib/updates.sh"
  cmd_drift_fix backup
  grep -q new-package "$HOME/curated/Brewfile"
  backup=$(find "$HOME/curated" -maxdepth 1 -name "Brewfile.backup-*" -exec basename {} \;)
  grep -q old-package "$HOME/curated/$backup"
  cmd_drift_restore "$backup"
  grep -q old-package "$HOME/curated/Brewfile"
'

if command -v mandoc >/dev/null 2>&1; then
  mandoc -T lint "$repo_root/man/brew-watchtower.1"
fi

echo "All tests passed."
