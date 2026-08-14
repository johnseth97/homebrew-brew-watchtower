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


cmd_groups() {
  [ -d "$GROUP_DIR" ] || return 0
  for file in "$GROUP_DIR"/*.conf; do
    [ -f "$file" ] || continue
    name=$(basename "$file" .conf)
    count=$(read_entries "$file" | wc -l | tr -d ' ')
    printf '%-20s %s item(s)\n' "$name" "$count"
  done
}


cmd_list() {
  if [ $# -eq 0 ]; then
    for file in "$GROUP_DIR"/*.conf; do
      [ -f "$file" ] || continue
      name=$(basename "$file" .conf)
      echo "[$name]"
      read_entries "$file" | awk -F '\t' '{printf "  %-8s %-32s %s\n", $1, $2, $3}'
    done
    return
  fi
  valid_group "$1" || die "invalid group name: $1"
  file=$(group_file "$1")
  [ -f "$file" ] || die "unknown group: $1"
  read_entries "$file" | awk -F '\t' '{printf "%-8s %-32s %s\n", $1, $2, $3}'
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
# I<TAB>group<TAB>type<TAB>token<TAB>mode.
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
      formula=*|cask=*)
        manifest_type=${manifest_line%%=*}
        manifest_value=${manifest_line#*=}
        manifest_token=${manifest_value%%,*}
        manifest_mode=${manifest_value#*,}
        [ "$manifest_token,$manifest_mode" = "$manifest_value" ] || { printf 'groups.conf:%s: item must be TOKEN,MODE\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1; }
        valid_token "$manifest_token" || { printf 'groups.conf:%s: invalid token\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1; }
        case "$manifest_mode" in auto|interactive) ;; *) printf 'groups.conf:%s: mode must be auto or interactive\n' "$manifest_line_number" >&2; rm -f "$manifest_entries"; return 1 ;; esac
        if awk -F '\t' -v token="$manifest_token" '$4 == token { found=1 } END { exit !found }' "$manifest_entries"; then
          printf 'groups.conf:%s: duplicate token in %s\n' "$manifest_line_number" "$manifest_group" >&2
          rm -f "$manifest_entries"
          return 1
        fi
        printf 'I\t%s\t%s\t%s\t%s\n' "$manifest_group" "$manifest_type" "$manifest_token" "$manifest_mode" >> "$manifest_entries"
        ;;
      *)
        printf 'groups.conf:%s: expected [group NAME], schedule=HH:MM, formula=TOKEN,MODE, or cask=TOKEN,MODE\n' "$manifest_line_number" >&2
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
# Syntax: [group NAME], schedule=HH:MM, formula=TOKEN,MODE, cask=TOKEN,MODE
# MODE is auto or interactive. Only groups declared here are changed by sync.

[group security]
schedule=09:30
# cask=tailscale-app,interactive
# cask=firefox,auto

[group dev-tools]
schedule=05:00
# formula=git,auto
# formula=ripgrep,auto
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
