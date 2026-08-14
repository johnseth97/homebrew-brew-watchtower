#!/bin/bash
# Shared implementation for brew-watchtower; sourced by bin/brew-watchtower.

usage() {
  cat <<'EOF'
Usage:
  brew-watchtower groups [init|sync|prune [--apply]|path]
  brew-watchtower list [GROUP]
  brew-watchtower add GROUP TYPE TOKEN [MODE]
  brew-watchtower remove GROUP TOKEN
  brew-watchtower check GROUP
  brew-watchtower run GROUP
  brew-watchtower status [GROUP]
  brew-watchtower drift
  brew-watchtower drift fix [--clobber]
  brew-watchtower drift restore BACKUP
  brew-watchtower blurb
  brew-watchtower config init
  brew-watchtower setup [HOUR [MINUTE]]
  brew-watchtower schedule GROUP HOUR MINUTE
  brew-watchtower version

TYPE: formula | cask
MODE: auto | interactive   (default: auto)

Examples:
  brew-watchtower groups init
  brew-watchtower groups sync
  brew-watchtower add security cask tailscale-app interactive
  brew-watchtower list security
  brew-watchtower check security
  brew-watchtower run security
  brew-watchtower remove security tailscale-app
  brew-watchtower drift fix
  brew-watchtower drift restore Brewfile.backup-20260813-180000
  brew-watchtower setup 9 30
EOF
}
# This config is deliberately parsed, never sourced. It controls only the
# user-owned presentation/export layer; root-owned update policy remains in
# GROUP_DIR. See `brew-watchtower config init` for the documented defaults.

load_config() {
  blurb=actionable
  prefix='⛫ Watchtower'
  detect_brewfile_drift=1
  brewfile="$USER_HOME/.dotfiles/macos/Brewfile"
  export_brewfile=0
  export_path="$CONFIG_DIR/Brewfile.generated"
  auto_fix_brewfile_drift=0
  groups_mode=mutable
  brewfile_backup_keep=5
  brewfile_backup_max_age_days=0

  [ -f "$CONFIG_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key=${line%%=*}
    value=${line#*=}
    [ "$key" != "$line" ] || continue
    case "$key" in
      blurb) case "$value" in actionable|always|never) blurb=$value ;; esac ;;
      prefix) [ -n "$value" ] && prefix=$value ;;
      detect_brewfile_drift) case "$value" in 0|1) detect_brewfile_drift=$value ;; esac ;;
      export_brewfile) case "$value" in 0|1) export_brewfile=$value ;; esac ;;
      auto_fix_brewfile_drift) case "$value" in 0|1) auto_fix_brewfile_drift=$value ;; esac ;;
      groups_mode) case "$value" in mutable|declarative) groups_mode=$value ;; esac ;;
      brewfile_backup_keep) case "$value" in ''|*[!0-9]*) ;; *) brewfile_backup_keep=$value ;; esac ;;
      brewfile_backup_max_age_days) case "$value" in ''|*[!0-9]*) ;; *) brewfile_backup_max_age_days=$value ;; esac ;;
      brewfile|export_path)
        case "$value" in '~/'*) value="$USER_HOME/${value#~/}" ;; esac
        case "$value" in /*)
          if [ "$key" = brewfile ]; then brewfile=$value; else export_path=$value; fi
          ;;
        esac
        ;;
    esac
  done < "$CONFIG_FILE"
}


cmd_config_show() {
  [ $# -eq 0 ] || die "config show takes no arguments"
  load_config
  printf 'config=%s\n' "$CONFIG_FILE"
  printf 'groups_file=%s\n' "$CONFIG_DIR/groups.conf"
  printf 'blurb=%s\n' "$blurb"
  printf 'prefix=%s\n' "$prefix"
  printf 'detect_brewfile_drift=%s\n' "$detect_brewfile_drift"
  printf 'brewfile=%s\n' "$brewfile"
  printf 'export_brewfile=%s\n' "$export_brewfile"
  printf 'export_path=%s\n' "$export_path"
  printf 'auto_fix_brewfile_drift=%s\n' "$auto_fix_brewfile_drift"
  printf 'groups_mode=%s\n' "$groups_mode"
  printf 'brewfile_backup_keep=%s\n' "$brewfile_backup_keep"
  printf 'brewfile_backup_max_age_days=%s\n' "$brewfile_backup_max_age_days"
}

cmd_config_path() {
  [ $# -eq 0 ] || die "config path takes no arguments"
  printf '%s\n' "$CONFIG_FILE"
}

cmd_config_init() {
  [ $# -eq 0 ] || die "config init takes no arguments"
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR" 2>/dev/null || true
  [ ! -e "$CONFIG_FILE" ] || die "config already exists: $CONFIG_FILE"
  cat > "$CONFIG_FILE" <<EOF
# Watchtower shell status and Brewfile drift settings.
# The shell prompt command only reads this file and Watchtower status files.
blurb=actionable
prefix=⛫ Watchtower
detect_brewfile_drift=1
brewfile=$USER_HOME/.dotfiles/macos/Brewfile
# Export always writes a generated snapshot, never the curated Brewfile above.
export_brewfile=0
export_path=$CONFIG_DIR/Brewfile.generated
# Opt in to regenerating brewfile when a Watchtower check/run detects drift.
auto_fix_brewfile_drift=0
# Set to declarative when groups.conf is managed outside the CLI. In that mode,
# add, remove, and schedule refuse direct policy changes; edit groups.conf and
# run brew-watchtower groups sync instead.
groups_mode=mutable
# Retain this many Watchtower-created backups; 0 keeps every backup.
brewfile_backup_keep=5
# Also delete backups older than this many days; 0 disables age pruning.
brewfile_backup_max_age_days=0
EOF
  chmod 600 "$CONFIG_FILE"
  printf 'Created %s\n' "$CONFIG_FILE"
}



die() {
  echo "$PROGRAM: $*" >&2
  exit 1
}


valid_group() {
  case "$1" in
    ''|*[!a-z0-9_-]*) return 1 ;;
    *) return 0 ;;
  esac
}


valid_token() {
  case "$1" in
    ''|*[!A-Za-z0-9@+._/-]*) return 1 ;;
    /*|*..*) return 1 ;;
    *) return 0 ;;
  esac
}


group_file() {
  printf '%s/%s.conf' "$GROUP_DIR" "$1"
}


require_user_runtime() {
  [ "$(id -u)" -ne 0 ] || die "checks and upgrades must run as your Homebrew user, not root"
  [ -x "$BREW" ] || die "Homebrew was not found at $BREW"
  mkdir -p "$STATE_DIR" "$LOG_DIR" "$CACHE_DIR"
  chmod 700 "$STATE_DIR" "$LOG_DIR" "$CACHE_DIR" 2>/dev/null || true
}


escalate_mutation() {
  if [ "$(id -u)" -ne 0 ]; then
    installed_runtime || die "protected runtime is not installed; run: brew-watchtower setup"
    exec /usr/bin/sudo "$POLICY_ROOT/bin/autoupdate" "$@"
  fi
}


install_runtime() {
  source_dir=$(cd "$(dirname "$0")" && pwd)
  source_lib_dir=$(cd "$source_dir/../lib" && pwd)
  [ -d "$source_lib_dir" ] || die "missing runtime library directory: $source_lib_dir"

  install -d -o root -g wheel -m 0755 "$POLICY_ROOT" "$POLICY_ROOT/bin" "$POLICY_ROOT/lib" "$GROUP_DIR"
  install -o root -g wheel -m 0755 "$source_dir/$(basename "$0")" "$POLICY_ROOT/bin/autoupdate"
  for module in "$source_lib_dir"/*.sh; do
    [ -f "$module" ] || continue
    install -o root -g wheel -m 0644 "$module" "$POLICY_ROOT/lib/$(basename "$module")"
  done
}

installed_runtime() {
  [ -x "$POLICY_ROOT/bin/autoupdate" ]
}
