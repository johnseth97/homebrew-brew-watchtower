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

