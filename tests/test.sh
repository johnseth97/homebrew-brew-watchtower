#!/bin/bash
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)

bash -n "$repo_root/bin/brew-watchtower" "$repo_root"/lib/*.sh
output=$("$repo_root/bin/brew-watchtower" version)
[ "$output" = "brew-watchtower 0.7.0" ]
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
grep -q '^auto_fix_brewfile_drift=0$' "$sandbox/.config/brew-watchtower/config"
grep -q '^brewfile_backup_keep=5$' "$sandbox/.config/brew-watchtower/config"
grep -q '^brewfile_backup_max_age_days=0$' "$sandbox/.config/brew-watchtower/config"
config_path=$(HOME="$sandbox" "$repo_root/bin/brew-watchtower" config path)
[ "$config_path" = "$sandbox/.config/brew-watchtower/config" ]
config_show=$(HOME="$sandbox" "$repo_root/bin/brew-watchtower" config show)
printf '%s\n' "$config_show" | grep -q '^blurb=actionable$'
printf '%s\n' "$config_show" | grep -q '^detect_brewfile_drift=1$'
printf '%s\n' "$config_show" | grep -q '^auto_fix_brewfile_drift=0$'
printf '%s\n' "$config_show" | grep -q '^brewfile_backup_keep=5$'
printf '%s\n' "$config_show" | grep -q '^brewfile_backup_max_age_days=0$'
printf '%s\n' "$config_show" | grep -q "^groups_file=$sandbox/.config/brew-watchtower/groups.conf$"

HOME="$sandbox" "$repo_root/bin/brew-watchtower" groups init >/dev/null
groups_path=$(HOME="$sandbox" "$repo_root/bin/brew-watchtower" groups path)
[ "$groups_path" = "$sandbox/.config/brew-watchtower/groups.conf" ]
[ -f "$groups_path" ]
cat > "$groups_path" <<'EOF'
[group security]
schedule=09:30
cask=tailscale-app,interactive
cask=firefox,auto
cask_glob=visual-studio-code*,interactive

[group dev-tools]
formula=git,auto
formula_glob=python@*,auto
EOF
normalized="$sandbox/groups.normalized"
PROGRAM=brew-watchtower REPO_ROOT="$repo_root" bash -c '
  source "$REPO_ROOT/lib/runtime.sh"
  source "$REPO_ROOT/lib/policy.sh"
  parse_groups_manifest "$1" "$2"
' _ "$groups_path" "$normalized"
grep -q $'^G\tsecurity\t09\t30$' "$normalized"
grep -q $'^I\tsecurity\tcask\ttailscale-app\tinteractive$' "$normalized"
grep -q $'^I\tsecurity\tcask\tvisual-studio-code\*\tinteractive$' "$normalized"
grep -q $'^I\tdev-tools\tformula\tgit\tauto$' "$normalized"
grep -q $'^I\tdev-tools\tformula\tpython@\*\tauto$' "$normalized"
printf '[group bad]\nformula=not allowed,auto\n' > "$sandbox/groups.invalid"
if PROGRAM=brew-watchtower REPO_ROOT="$repo_root" bash -c '
  source "$REPO_ROOT/lib/runtime.sh"
  source "$REPO_ROOT/lib/policy.sh"
  parse_groups_manifest "$1" "$2"
' _ "$sandbox/groups.invalid" "$sandbox/groups.invalid.out" 2>/dev/null; then
  echo "invalid groups manifest unexpectedly passed" >&2
  exit 1
fi
printf '[group bad]\nformula_glob=python,auto\n' > "$sandbox/groups.invalid-glob"
if PROGRAM=brew-watchtower REPO_ROOT="$repo_root" bash -c '
  source "$REPO_ROOT/lib/runtime.sh"
  source "$REPO_ROOT/lib/policy.sh"
  parse_groups_manifest "$1" "$2"
' _ "$sandbox/groups.invalid-glob" "$sandbox/groups.invalid-glob.out" 2>/dev/null; then
  echo "glob-free selector unexpectedly passed" >&2
  exit 1
fi

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
if [ "$1" = list ]; then
  case "$2" in
    --formula) printf '%s\n' git python@3.12 python@3.13 ripgrep ;;
    --cask) printf '%s\n' firefox tailscale-app visual-studio-code visual-studio-code-insiders ;;
  esac
  exit 0
fi
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
  shift 2
  while [ $# -gt 0 ]; do
    if [ "$1" = --file ]; then
      grep -q new-package "$2"
      exit $?
    fi
    shift
  done
fi
exit 1
EOF
chmod 700 "$fake_brew"
mkdir -p "$sandbox/groups"
cat > "$sandbox/groups/dev-tools.conf" <<'EOF'
# type	selector	mode
formula	git	auto
formula	python@*	auto
cask	visual-studio-code*	interactive
EOF
resolved_groups=$(TEST_BREW="$fake_brew" TEST_GROUP_DIR="$sandbox/groups" REPO_ROOT="$repo_root" bash -c '
  set -eu
  PROGRAM=brew-watchtower
  BREW="$TEST_BREW"
  GROUP_DIR="$TEST_GROUP_DIR"
  source "$REPO_ROOT/lib/runtime.sh"
  source "$REPO_ROOT/lib/policy.sh"
  cmd_groups
')
printf '%s\n' "$resolved_groups" | grep -q '^\[dev-tools\] 5 matched item(s)$'
printf '%s\n' "$resolved_groups" | grep -q '^  formula  python@3.12'
printf '%s\n' "$resolved_groups" | grep -q '^  formula  python@3.13'
printf '%s\n' "$resolved_groups" | grep -q '^  cask     visual-studio-code '
printf '%s\n' "$resolved_groups" | grep -q '^  cask     visual-studio-code-insiders '
cat > "$sandbox/groups/conflict.conf" <<'EOF'
formula	python@*	auto
formula	python@3.12	interactive
EOF
if TEST_BREW="$fake_brew" TEST_GROUP_DIR="$sandbox/groups" REPO_ROOT="$repo_root" bash -c '
  set -eu
  PROGRAM=brew-watchtower
  BREW="$TEST_BREW"
  GROUP_DIR="$TEST_GROUP_DIR"
  source "$REPO_ROOT/lib/runtime.sh"
  source "$REPO_ROOT/lib/policy.sh"
  resolve_entries "$GROUP_DIR/conflict.conf"
' >/dev/null 2>&1; then
  echo "conflicting selector modes unexpectedly passed" >&2
  exit 1
fi
mkdir -p "$sandbox/curated"
printf '# curated\nbrew "old-package"\n' > "$sandbox/curated/Brewfile"
cat > "$sandbox/.config/brew-watchtower/config" <<EOF
blurb=never
detect_brewfile_drift=1
brewfile=$sandbox/curated/Brewfile
export_brewfile=0
auto_fix_brewfile_drift=1
brewfile_backup_keep=1
brewfile_backup_max_age_days=0
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
  record_brewfile_state "$HOME/Library/Application Support/Homebrew AutoUpdate/auto.status"
  grep -q '^brewfile_drift=clean$' "$HOME/Library/Application Support/Homebrew AutoUpdate/auto.status"
  grep -q '^brewfile_auto_fix=success$' "$HOME/Library/Application Support/Homebrew AutoUpdate/auto.status"
  grep -q new-package "$HOME/curated/Brewfile"
  [ "$(find "$HOME/curated" -maxdepth 1 -name "Brewfile.backup-*" | wc -l | tr -d " ")" = 1 ]
'

if command -v mandoc >/dev/null 2>&1; then
  mandoc -T lint "$repo_root/man/brew-watchtower.1"
fi

echo "All tests passed."
