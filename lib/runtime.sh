#!/bin/bash
# Shared implementation for brew-watchtower; sourced by bin/brew-watchtower.

usage() {
  cat <<'EOF'
Usage:
  brew-watchtower groups
  brew-watchtower list [GROUP]
  brew-watchtower add GROUP TYPE TOKEN [MODE]
  brew-watchtower remove GROUP TOKEN
  brew-watchtower check GROUP
  brew-watchtower run GROUP
  brew-watchtower status [GROUP]
  brew-watchtower blurb
  brew-watchtower config init
  brew-watchtower setup [HOUR [MINUTE]]
  brew-watchtower schedule GROUP HOUR MINUTE
  brew-watchtower version

TYPE: formula | cask
MODE: auto | interactive   (default: auto)

Examples:
  brew-watchtower add security cask tailscale-app interactive
  brew-watchtower list security
  brew-watchtower check security
  brew-watchtower run security
  brew-watchtower remove security tailscale-app
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

