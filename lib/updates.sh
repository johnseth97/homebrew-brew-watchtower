#!/bin/bash
# Shared implementation for brew-watchtower; sourced by bin/brew-watchtower.

notify() {
  title=$1 body=$2
  /usr/bin/osascript -e "display notification $(printf '%s' "$body" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "\"%s\"", $0}') with title \"$title\"" >/dev/null 2>&1 || true
}


acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    die "another Homebrew AutoUpdate job appears to be running"
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT HUP INT TERM
}


outdated_token() {
  type=$1 token=$2
  case "$type" in
    formula) "$BREW" outdated --formula "$token" 2>/dev/null | grep -Fxq "$token" ;;
    cask) "$BREW" outdated --cask --greedy-auto-updates "$token" 2>/dev/null | grep -Fxq "$token" ;;
  esac
}


prune_brewfile_backups() {
  backup_dir=$(dirname "$brewfile")
  backup_pattern="$(basename "$brewfile").backup-*"

  if [ "$brewfile_backup_max_age_days" -gt 0 ]; then
    find "$backup_dir" -maxdepth 1 -type f -name "$backup_pattern" -mtime "+$brewfile_backup_max_age_days" -delete
  fi

  [ "$brewfile_backup_keep" -gt 0 ] || return 0
  backup_list=$(mktemp "$CACHE_DIR/brew-watchtower-backups.XXXXXX") || return 1
  while IFS= read -r backup_path; do
    printf '%s\t%s\n' "$(stat -f '%m' "$backup_path")" "$backup_path"
  done < <(find "$backup_dir" -maxdepth 1 -type f -name "$backup_pattern") | sort -rn > "$backup_list"
  backup_count=0
  while IFS="$(printf '\t')" read -r backup_mtime backup_path; do
    [ -n "$backup_path" ] || continue
    backup_count=$((backup_count + 1))
    [ "$backup_count" -le "$brewfile_backup_keep" ] || rm -f "$backup_path"
  done < "$backup_list"
  rm -f "$backup_list"
  return 0
}


perform_drift_fix() {
  mode=$1
  if [ "$mode" = backup ]; then
    backup_path=$(drift_backup_file "$brewfile") || return 1
    printf 'Backed up %s to %s\n' "$brewfile" "$backup_path"
  fi
  HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" bundle dump --force --file "$brewfile" || return 1
  prune_brewfile_backups || return 1
  printf 'Replaced %s with the current Homebrew bundle.\n' "$brewfile"
}


record_brewfile_state() {
  statusfile=$1
  auto_fix_mode=${2:-enabled}
  load_config
  drift=disabled
  exported=disabled
  auto_fixed=disabled

  if [ "$detect_brewfile_drift" = 1 ]; then
    if [ ! -f "$brewfile" ]; then
      drift=unavailable
    elif HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" bundle check --file "$brewfile" >/dev/null 2>&1; then
      drift=clean
    else
      drift=detected
      if [ "$auto_fix_brewfile_drift" = 1 ] && [ "$auto_fix_mode" = enabled ]; then
        if perform_drift_fix backup && HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" bundle check --file "$brewfile" >/dev/null 2>&1; then
          drift=clean
          auto_fixed=success
        else
          auto_fixed=failed
        fi
      fi
    fi
  fi

  if [ "$export_brewfile" = 1 ]; then
    mkdir -p "$(dirname "$export_path")"
    if HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" bundle dump --force --file "$export_path" >/dev/null 2>&1; then
      chmod 600 "$export_path" 2>/dev/null || true
      exported=success
    else
      exported=failed
    fi
  fi

  printf 'brewfile_checked=%s\nbrewfile_drift=%s\nbrewfile_auto_fix=%s\nbrewfile_export=%s\n' "$(date +%s)" "$drift" "$auto_fixed" "$exported" >> "$statusfile"
}


cmd_drift() {
  [ $# -eq 0 ] || die "drift takes no arguments"
  require_user_runtime
  statusfile="$STATE_DIR/drift.status"
  load_config

  printf 'last_run=%s\nresult=success\npending_interactive=\n' "$(date +%s)" > "$statusfile"
  record_brewfile_state "$statusfile"
  drift=$(awk -F= '$1 == "brewfile_drift" { print $2; exit }' "$statusfile")

  case "$drift" in
    clean)
      printf 'Brewfile matches installed Homebrew state: %s\n' "$brewfile"
      ;;
    detected)
      printf 'Brewfile drift detected: %s\n' "$brewfile" >&2
      printf 'Run: %s bundle check --file %s --verbose\n' "$BREW" "$brewfile" >&2
      return 1
      ;;
    unavailable)
      printf 'Configured Brewfile is unavailable: %s\n' "$brewfile" >&2
      return 2
      ;;
    disabled)
      printf 'Brewfile drift checking is disabled in %s\n' "$CONFIG_FILE"
      ;;
    *)
      printf 'Unable to determine Brewfile drift state.\n' >&2
      return 2
      ;;
  esac
}

drift_backup_name() {
  printf '%s.backup-%s' "$(basename "$brewfile")" "$(date '+%Y%m%d-%H%M%S')"
}


drift_backup_path() {
  backup_dir=$(dirname "$brewfile")
  backup_name=$(drift_backup_name)
  backup_path="$backup_dir/$backup_name"
  backup_index=1
  while [ -e "$backup_path" ]; do
    backup_path="$backup_dir/$backup_name-$backup_index"
    backup_index=$((backup_index + 1))
  done
  printf '%s\n' "$backup_path"
}


drift_backup_file() {
  source_file=$1
  [ -f "$source_file" ] || return 1
  backup_path=$(drift_backup_path)
  cp -p "$source_file" "$backup_path" || return 1
  printf '%s\n' "$backup_path"
}


refresh_drift_status() {
  statusfile="$STATE_DIR/drift.status"
  printf 'last_run=%s\nresult=success\npending_interactive=\n' "$(date +%s)" > "$statusfile"
  record_brewfile_state "$statusfile" disabled
}


cmd_drift_fix() {
  mode=$1
  require_user_runtime
  load_config
  [ -f "$brewfile" ] || die "configured Brewfile is unavailable: $brewfile"

  perform_drift_fix "$mode" || die "could not write Brewfile: $brewfile"
  refresh_drift_status
}


cmd_drift_restore() {
  backup_name=$1
  require_user_runtime
  load_config
  case "$backup_name" in
    "$(basename "$brewfile").backup-"*) ;;
    *) die "backup must be a sibling filename beginning $(basename "$brewfile").backup-" ;;
  esac
  case "$backup_name" in *'/'*|*'..'*) die "invalid backup filename: $backup_name" ;; esac
  backup_path="$(dirname "$brewfile")/$backup_name"
  [ -f "$backup_path" ] || die "backup does not exist: $backup_path"

  if [ -f "$brewfile" ]; then
    current_backup=$(drift_backup_file "$brewfile") || die "could not back up current Brewfile: $brewfile"
    printf 'Backed up current %s to %s\n' "$brewfile" "$current_backup"
  fi
  cp -p "$backup_path" "$brewfile" || die "could not restore Brewfile from: $backup_path"
  restored_from=$backup_path
  prune_brewfile_backups || die "could not prune Brewfile backups"
  refresh_drift_status
  printf 'Restored %s from %s\n' "$brewfile" "$restored_from"
}


cmd_blurb() {
  [ $# -eq 0 ] || die "blurb takes no arguments"
  load_config
  [ "$blurb" != never ] || return 0

  messages=""
  newest=0
  found=0
  drift_reported=0
  for file in "$STATE_DIR"/*.status; do
    [ -f "$file" ] || continue
    found=1
    group=$(basename "$file" .status)
    result=$(awk -F= '$1 == "result" { print $2; exit }' "$file")
    pending=$(awk -F= '$1 == "pending_interactive" { print $2; exit }' "$file")
    drift=$(awk -F= '$1 == "brewfile_drift" { print $2; exit }' "$file")
    last_run=$(awk -F= '$1 == "last_run" { print $2; exit }' "$file")
    case "$last_run" in ''|*[!0-9]*) ;; *) [ "$last_run" -gt "$newest" ] && newest=$last_run ;; esac
    [ "$result" = failed ] && messages="$messages; $group failed"
    [ -n "$pending" ] && messages="$messages; $group: update $pending"
    if [ "$drift" = detected ] && [ "$drift_reported" = 0 ]; then
      messages="$messages; Brewfile drift detected"
      drift_reported=1
    fi
  done

  if [ -n "$messages" ]; then
    printf '%s: %s\n' "$prefix" "${messages#; }"
  elif [ "$blurb" = always ]; then
    if [ "$found" = 0 ]; then
      printf '%s: no scheduled runs recorded\n' "$prefix"
    elif [ "$newest" -gt 0 ]; then
      printf '%s: all clear (last check %s)\n' "$prefix" "$(date -r "$newest" '+%Y-%m-%d %H:%M')"
    else
      printf '%s: all clear\n' "$prefix"
    fi
  fi
}


cmd_check_or_run() {
  action=$1 group=$2
  valid_group "$group" || die "invalid group name: $group"
  file=$(group_file "$group")
  [ -f "$file" ] || die "unknown group: $group"
  require_user_runtime
  acquire_lock

  logfile="$LOG_DIR/$group.log"
  statusfile="$STATE_DIR/$group.status"
  exec >> "$logfile" 2>&1
  echo "===== $(date '+%Y-%m-%d %H:%M:%S %Z') action=$action group=$group ====="

  if ! "$BREW" update; then
    printf 'last_run=%s\nresult=failed\nreason=brew_update\n' "$(date +%s)" > "$statusfile"
    record_brewfile_state "$statusfile"
    notify "Homebrew AutoUpdate failed" "$group: brew update failed"
    return 1
  fi

  pending_auto=""
  pending_interactive=""
  while IFS="$(printf '\t')" read -r type token mode; do
    [ -n "$type" ] || continue
    valid_token "$token" || { echo "Rejected invalid token in $file: $token"; continue; }
    case "$type:$mode" in formula:auto|formula:interactive|cask:auto|cask:interactive) ;; *) echo "Rejected invalid entry: $type $token $mode"; continue ;; esac
    if outdated_token "$type" "$token"; then
      echo "OUTDATED $type $token mode=$mode"
      if [ "$mode" = interactive ]; then
        pending_interactive="$pending_interactive $token"
      else
        pending_auto="$pending_auto $type:$token"
      fi
    fi
  done <<EOF
$(read_entries "$file")
EOF

  failures=0
  if [ "$action" = run ]; then
    for entry in $pending_auto; do
      type=${entry%%:*}; token=${entry#*:}
      echo "UPGRADING $type $token"
      if [ "$type" = cask ]; then
        "$BREW" upgrade --cask --greedy-auto-updates "$token" || failures=$((failures + 1))
      else
        "$BREW" upgrade --formula "$token" || failures=$((failures + 1))
      fi
    done

    # Interactive entries are run only from an attached Terminal. launchd has
    # no TTY and therefore only reports them.
    if [ -t 0 ]; then
      for token in $pending_interactive; do
        echo "UPGRADING interactive cask $token"
        env -u NONINTERACTIVE "$BREW" upgrade --cask --greedy-auto-updates "$token" || failures=$((failures + 1))
      done
      pending_interactive=""
    fi
  fi

  now=$(date +%s)
  if [ "$failures" -gt 0 ]; then
    printf 'last_run=%s\nresult=failed\nfailures=%s\n' "$now" "$failures" > "$statusfile"
    notify "Homebrew AutoUpdate failed" "$group: $failures upgrade(s) failed; see $logfile"
    return 1
  fi
  printf 'last_run=%s\nresult=success\npending_interactive=%s\n' "$now" "${pending_interactive# }" > "$statusfile"
  record_brewfile_state "$statusfile"
  if [ -n "$pending_interactive" ]; then
    notify "Homebrew updates need attention" "$group:${pending_interactive}; run brew-watchtower run $group"
  fi
  echo "Completed successfully."
}


cmd_status() {
  if [ $# -eq 1 ]; then
    valid_group "$1" || die "invalid group name: $1"
    file="$STATE_DIR/$1.status"
    if [ -f "$file" ]; then
      echo "[$1]"
      sed 's/^/  /' "$file"
    else
      echo "No runs recorded yet."
    fi
    return
  else
    found=0
  fi
  for file in "$STATE_DIR"/*.status; do
    [ -f "$file" ] || continue
    found=1
    group=$(basename "$file" .status)
    echo "[$group]"
    sed 's/^/  /' "$file"
  done
  [ "$found" -eq 1 ] || echo "No runs recorded yet."
}

