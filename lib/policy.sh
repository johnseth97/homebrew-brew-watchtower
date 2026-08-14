#!/bin/bash
# Shared implementation for brew-watchtower; sourced by bin/brew-watchtower.

read_entries() {
  file=$1
  [ -f "$file" ] || return 0
  awk -F '\t' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    NF == 3 { print $1 "\t" $2 "\t" $3 }
  ' "$file"
}

valid_selector() {
  case "$1" in
    ''|*[!A-Za-z0-9@+._/\*?\[\]-]*) return 1 ;;
    /*|*..*) return 1 ;;
    *) return 0 ;;
  esac
}

has_glob() {
  case "$1" in *\**|*\?*|*\[*) return 0 ;; *) return 1 ;; esac
}

installed_tokens() {
  case "$1" in
    formula) "$BREW" list --formula 2>/dev/null ;;
    cask) "$BREW" list --cask 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# Expand exact tokens and shell-style glob selectors against packages installed
# on this host. The selector is used only as a `case` pattern; it is never
# evaluated as shell code. A conflicting mode for the same resolved package is
# rejected rather than making an unattended-update decision implicitly.
resolve_entries() {
  file=$1
  matches=$(mktemp /tmp/brew-watchtower-matches.XXXXXX) || return 1
  while IFS="$(printf '\t')" read -r type selector mode; do
    [ -n "$type" ] || continue
    case "$type:$mode" in formula:auto|formula:interactive|cask:auto|cask:interactive) ;; *) printf 'Rejected invalid entry: %s %s %s\n' "$type" "$selector" "$mode" >&2; rm -f "$matches"; return 1 ;; esac
    valid_selector "$selector" || { printf 'Rejected invalid selector in %s: %s\n' "$file" "$selector" >&2; rm -f "$matches"; return 1; }
    installed=$(installed_tokens "$type") || { printf 'Could not list installed %ss.\n' "$type" >&2; rm -f "$matches"; return 1; }
    while IFS= read -r token; do
      [ -n "$token" ] || continue
      case "$token" in
        $selector) printf '%s\t%s\t%s\n' "$type" "$token" "$mode" >> "$matches" ;;
      esac
    done <<EOF
$installed
EOF
  done <<EOF
$(read_entries "$file")
EOF

  if ! awk -F "$(printf '\t')" '
    { key = $1 FS $2; if (mode[key] != "" && mode[key] != $3) { printf "Conflicting modes for %s: %s and %s\\n", key, mode[key], $3 > "/dev/stderr"; failed = 1 } mode[key] = $3 }
    END { exit failed }
  ' "$matches"; then
    rm -f "$matches"
    return 1
  fi
  sort -u "$matches"
  rm -f "$matches"
}


cmd_groups() {
  [ -d "$GROUP_DIR" ] || return 0
  for file in "$GROUP_DIR"/*.conf; do
    [ -f "$file" ] || continue
    name=$(basename "$file" .conf)
    matches=$(resolve_entries "$file") || die "could not resolve group: $name"
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
    printf '[%s] %s matched item(s)\n' "$name" "$count"
    [ -z "$matches" ] || printf '%s\n' "$matches" | awk -F "$(printf '\t')" '{printf "  %-8s %-32s %s\n", $1, $2, $3}'
  done
}


cmd_list() {
  if [ $# -eq 0 ]; then
    for file in "$GROUP_DIR"/*.conf; do
      [ -f "$file" ] || continue
      name=$(basename "$file" .conf)
      echo "[$name]"
      resolve_entries "$file" | awk -F '\t' '{printf "  %-8s %-32s %s\n", $1, $2, $3}'
    done
    return
  fi
  valid_group "$1" || die "invalid group name: $1"
  file=$(group_file "$1")
  [ -f "$file" ] || die "unknown group: $1"
  resolve_entries "$file" | awk -F '\t' '{printf "%-8s %-32s %s\n", $1, $2, $3}'
}


cmd_add() {
  [ $# -ge 3 ] && [ $# -le 4 ] || die "add requires GROUP TYPE TOKEN [MODE]"
  group=$1 type=$2 token=$3 mode=${4:-auto}
  valid_group "$group" || die "invalid group name: $group"
  valid_token "$token" || die "invalid Homebrew token: $token"
  case "$type" in formula|cask) ;; *) die "TYPE must be formula or cask" ;; esac
  case "$mode" in auto|interactive) ;; *) die "MODE must be auto or interactive" ;; esac
  escalate_mutation add "$group" "$type" "$token" "$mode"

  file=$(group_file "$group")
  mkdir -p "$GROUP_DIR"
  tmp=$(mktemp /tmp/autoupdate-group.XXXXXX) || exit 1
  if [ -f "$file" ]; then
    awk -F '\t' -v token="$token" '$2 != token' "$file" > "$tmp"
  else
    printf '# type\ttoken\tmode\n' > "$tmp"
  fi
  printf '%s\t%s\t%s\n' "$type" "$token" "$mode" >> "$tmp"
  sort -t "$(printf '\t')" -k2,2 "$tmp" -o "$tmp"
  chown root:wheel "$tmp"
  chmod 0644 "$tmp"
  mv "$tmp" "$file"
  echo "Added $token to $group as $type ($mode)."
}


cmd_remove() {
  [ $# -eq 2 ] || die "remove requires GROUP TOKEN"
  group=$1 token=$2
  valid_group "$group" || die "invalid group name: $group"
  valid_token "$token" || die "invalid Homebrew token: $token"
  escalate_mutation remove "$group" "$token"

  file=$(group_file "$group")
  [ -f "$file" ] || die "unknown group: $group"
  grep -Fq "$(printf '\t')$token$(printf '\t')" "$file" || die "$token is not in $group"
  tmp=$(mktemp /tmp/autoupdate-group.XXXXXX) || exit 1
  awk -F '\t' -v token="$token" '$2 != token' "$file" > "$tmp"
  chown root:wheel "$tmp"
  chmod 0644 "$tmp"
  mv "$tmp" "$file"
  echo "Removed $token from $group."
}



# groups.conf is a strict, declarative stanza format. It is parsed, never
# sourced, so a Stow-managed file cannot execute code during a privileged sync.
# Normalized records are G<TAB>group<TAB>hour<TAB>minute and
# I<TAB>group<TAB>type<TAB>selector<TAB>mode. Selectors are exact package
# tokens or shell-style globs and resolve against installed packages at use.
parse_groups_manifest() {
  manifest_source=$1
  manifest_output=$2
  : > "$manifest_output" || return 1
  manifest_entries=$(mktemp /tmp/brew-watchtower-manifest.XXXXXX) || return 1
  manifest_group=""
  manifest_hour=""
  manifest_minute=""
  manifest_line_number=0

  manifest_flush() {
    [ -n "$manifest_group" ] || return 0
    printf 'G\t%s\t%s\t%s\n' "$manifest_group" "$manifest_hour" "$manifest_minute" >> "$manifest_output"
    cat "$manifest_entries" >> "$manifest_output"
    : > "$manifest_entries"
    manifest_group=""
    manifest_hour=""
    manifest_minute=""
  }

  while IFS= read -r manifest_line || [ -n "$manifest_line" ]; do
    manifest_line_number=$((manifest_line_number + 1))
    manifest_line=${manifest_line%%#*}
    manifest_line=$(printf '%s' "$manifest_line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$manifest_line" ] || continue

    if [[ "$manifest_line" =~ ^\[group[[:space:]]+([a-z0-9_-]+)\]$ ]]; then
      manifest_flush || { rm -f "$manifest_entries"; return 1; }
      manifest_group=${BASH_REMATCH[1]}
      if awk -F '\t' -v group="$manifest_group" '$1 == "G" && $2 == group { found=1 } END { exit !found }' "$manifest_output"; then
        printf 'groups.conf:%s: duplicate group %s\n' "$manifest_line_number" "$manifest_group" >&2
        rm -f "$manifest_entries"
        return 1
      fi
      continue
    fi
    [ -n "$manifest_group" ] || { printf 'groups.conf:%s: entry outside a group\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1; }

    case "$manifest_line" in
      schedule=*)
        [ -z "$manifest_hour" ] || { printf 'groups.conf:%s: duplicate schedule\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1; }
        manifest_schedule=${manifest_line#schedule=}
        case "$manifest_schedule" in [0-2][0-9]:[0-5][0-9]) ;; *) printf 'groups.conf:%s: schedule must be HH:MM\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1 ;; esac
        manifest_hour=${manifest_schedule%%:*}
        manifest_minute=${manifest_schedule#*:}
        [ "$manifest_hour" -le 23 ] || { printf 'groups.conf:%s: hour must be 00 through 23\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1; }
        ;;
      formula=*|cask=*|formula_glob=*|cask_glob=*)
        manifest_key=${manifest_line%%=*}
        manifest_type=${manifest_key%_glob}
        manifest_value=${manifest_line#*=}
        manifest_selector=${manifest_value%%,*}
        manifest_mode=${manifest_value#*,}
        [ "$manifest_selector,$manifest_mode" = "$manifest_value" ] || { printf 'groups.conf:%s: item must be SELECTOR,MODE\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1; }
        if [ "$manifest_key" = "$manifest_type" ]; then
          valid_token "$manifest_selector" || { printf 'groups.conf:%s: invalid token\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1; }
        else
          valid_selector "$manifest_selector" && has_glob "$manifest_selector" || { printf 'groups.conf:%s: glob selector must contain *, ?, or []\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1; }
        fi
        case "$manifest_mode" in auto|interactive) ;; *) printf 'groups.conf:%s: mode must be auto or interactive\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1 ;; esac
        if awk -F '\t' -v type="$manifest_type" -v selector="$manifest_selector" '$3 == type && $4 == selector { found=1 } END { exit !found }' "$manifest_entries"; then
          printf 'groups.conf:%s: duplicate selector in %s\n' "$manifest_line_number" "$manifest_group" >&2
          rm -f "$manifest_entries"
          return 1
        fi
        printf 'I\t%s\t%s\t%s\t%s\n' "$manifest_group" "$manifest_type" "$manifest_selector" "$manifest_mode" >> "$manifest_entries"
        ;;
      *)
        printf 'groups.conf:%s: expected [group NAME], schedule=HH:MM, formula=TOKEN,MODE, cask=TOKEN,MODE, formula_glob=PATTERN,MODE, or cask_glob=PATTERN,MODE\n' "$manifest_line_number" >&2
        rm -f "$manifest_entries"
        return 1
        ;;
    esac
  done < "$manifest_source"
  manifest_flush || { rm -f "$manifest_entries"; return 1; }
  rm -f "$manifest_entries"
  [ -s "$manifest_output" ] || { printf 'groups.conf: no groups declared\n' >&2; return 1; }
}


cmd_groups_init() {
  [ $# -eq 0 ] || die "groups init takes no arguments"
  groups_file="$CONFIG_DIR/groups.conf"
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR" 2>/dev/null || true
  [ ! -e "$groups_file" ] || die "groups config already exists: $groups_file"
  cat > "$groups_file" <<'GROUPS_EOF'
# Declarative Watchtower group policy. Run: brew-watchtower groups sync
# Syntax: [group NAME], schedule=HH:MM, formula=TOKEN,MODE, cask=TOKEN,MODE,
# formula_glob=PATTERN,MODE, cask_glob=PATTERN,MODE
# MODE is auto or interactive. Only groups declared here are changed by sync.

[group security]
schedule=09:30
# cask=tailscale-app,interactive
# cask=firefox,auto

[group dev-tools]
schedule=05:00
# formula=git,auto
# formula=ripgrep,auto
# formula_glob=python@*,auto
GROUPS_EOF
  chmod 600 "$groups_file"
  printf 'Created %s\n' "$groups_file"
}


cmd_groups_path() {
  [ $# -eq 0 ] || die "groups path takes no arguments"
  printf '%s\n' "$CONFIG_DIR/groups.conf"
}


cmd_groups_sync() {
  [ $# -eq 0 ] || die "groups sync takes no arguments"
  groups_file="$CONFIG_DIR/groups.conf"
  [ -f "$groups_file" ] || die "groups config is missing; run: brew-watchtower groups init"
  normalized=$(mktemp /tmp/brew-watchtower-manifest.XXXXXX) || die "could not create temporary manifest"
  trap 'rm -f "$normalized"' EXIT HUP INT TERM
  parse_groups_manifest "$groups_file" "$normalized" || die "groups config is invalid: $groups_file"
  rm -f "$normalized"
  trap - EXIT HUP INT TERM
  if [ "$(id -u)" -ne 0 ]; then
    installed_runtime || die "protected runtime is not installed; run: brew-watchtower setup"
    exec /usr/bin/sudo "$POLICY_ROOT/bin/autoupdate" __groups_sync "$(id -un)" "$(id -u)" "$USER_HOME"
  fi
  die "groups sync must be started by a non-root user"
}


cmd_groups_sync_internal() {
  [ "$(id -u)" -eq 0 ] || die "internal group sync requires root"
  [ $# -eq 3 ] || die "invalid internal group sync invocation"
  target_user=$1 target_uid=$2 target_home=$3
  groups_file="$target_home/.config/brew-watchtower/groups.conf"
  [ -f "$groups_file" ] || die "groups config is missing: $groups_file"
  normalized=$(mktemp /tmp/brew-watchtower-manifest.XXXXXX) || die "could not create temporary manifest"
  trap 'rm -f "$normalized"' EXIT HUP INT TERM
  parse_groups_manifest "$groups_file" "$normalized" || die "groups config is invalid: $groups_file"

  while IFS="$(printf '\t')" read -r record group hour minute; do
    [ "$record" = G ] || continue
    tmp=$(mktemp /tmp/brew-watchtower-group.XXXXXX) || die "could not create group file"
    printf '# type\ttoken\tmode\n' > "$tmp"
    awk -F '\t' -v group="$group" '$1 == "I" && $2 == group { print $3 "\t" $4 "\t" $5 }' "$normalized" | sort -t "$(printf '\t')" -k2,2 >> "$tmp"
    install -o root -g wheel -m 0644 "$tmp" "$(group_file "$group")"
    rm -f "$tmp"
    [ -z "$hour" ] || write_launchagent "$target_user" "$target_uid" "$target_home" "$group" "$hour" "$minute"
  done < "$normalized"
  rm -f "$normalized"
  trap - EXIT HUP INT TERM
  echo "Synchronized declarative groups from $groups_file."
}
