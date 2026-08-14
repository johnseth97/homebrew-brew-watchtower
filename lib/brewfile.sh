#!/bin/bash
# Brewfile drift, export, and group-exclusion projection helpers.

excluded_brewfile_tokens() {
  groups_file="$CONFIG_DIR/groups.conf"
  [ -f "$groups_file" ] || return 0
  normalized=$(mktemp "$CACHE_DIR/brew-watchtower-groups.XXXXXX") || return 1
  parse_groups_manifest "$groups_file" "$normalized" || { rm -f "$normalized"; return 1; }
  awk -F '\t' '$1 == "G" && $7 == "exclude" { print $2 }' "$normalized" | while IFS= read -r group; do
    resolve_entries "$(group_file "$group")" | awk -F '\t' '{print $1 "\t" $2}'
  done
  rm -f "$normalized"
}

project_brewfile() {
  source=$1 target=$2
  excluded=$(mktemp "$CACHE_DIR/brew-watchtower-excluded.XXXXXX") || return 1
  excluded_brewfile_tokens | sort -u > "$excluded"
  awk -v excluded="$excluded" '
    BEGIN { while ((getline line < excluded) > 0) ignored[line]=1 }
    /^brew "/ { type="formula"; token=$0; sub(/^brew "/, "", token); sub(/".*/, "", token); sub(/^.*\//, "", token); if (ignored[type "\t" token]) next }
    /^cask "/ { type="cask"; token=$0; sub(/^cask "/, "", token); sub(/".*/, "", token); sub(/^.*\//, "", token); if (ignored[type "\t" token]) next }
    { print }
  ' "$source" > "$target"
  rm -f "$excluded"
}
