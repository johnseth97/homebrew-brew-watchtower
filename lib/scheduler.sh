#!/bin/bash
# Shared implementation for brew-watchtower; sourced by bin/brew-watchtower.

plist_path() {
  printf '%s/Library/LaunchAgents/local.homebrew-autoupdate.%s.plist' "$1" "$2"
}


write_launchagent() {
  target_user=$1 target_uid=$2 target_home=$3 group=$4 frequency=$5 day=$6 hour=$7 minute=$8
  valid_group "$group" || die "invalid group name: $group"
  case "$frequency" in hourly|daily|weekly|monthly) ;; *) die "invalid schedule frequency" ;; esac
  case "$hour" in ''|*[!0-9]*) [ "$frequency" = hourly ] || die "hour must be 0 through 23" ;; esac
  case "$minute" in ''|*[!0-9]*) die "minute must be 0 through 59" ;; esac
  [ "$frequency" = hourly ] || { [ "$hour" -ge 0 ] && [ "$hour" -le 23 ] || die "hour must be 0 through 23"; }
  [ "$minute" -ge 0 ] && [ "$minute" -le 59 ] || die "minute must be 0 through 59"

  agent_dir="$target_home/Library/LaunchAgents"
  log_dir="$target_home/Library/Logs/Homebrew AutoUpdate"
  agent=$(plist_path "$target_home" "$group")
  mkdir -p "$agent_dir" "$log_dir"
  tmp=$(mktemp /tmp/brew-watchtower-agent.XXXXXX) || exit 1
  case "$frequency" in
    hourly) calendar="<key>Minute</key><integer>$minute</integer>" ;;
    daily) calendar="<key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer>" ;;
    weekly) case "$day" in sun) weekday=0;;mon)weekday=1;;tue)weekday=2;;wed)weekday=3;;thu)weekday=4;;fri)weekday=5;;sat)weekday=6;;*)die "invalid weekday";;esac; calendar="<key>Weekday</key><integer>$weekday</integer><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer>" ;;
    monthly) calendar="<key>Day</key><integer>$day</integer><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer>" ;;
  esac
  cat > "$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.homebrew-autoupdate.$group</string>
  <key>ProgramArguments</key>
  <array>
    <string>$POLICY_ROOT/bin/autoupdate</string>
    <string>run</string>
    <string>$group</string>
  </array>
  <key>StartCalendarInterval</key><dict>$calendar</dict>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>StandardOutPath</key>
  <string>$log_dir/launchd-$group.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/launchd-$group.log</string>
</dict>
</plist>
EOF
  /usr/bin/plutil -lint "$tmp" >/dev/null || die "generated an invalid LaunchAgent"
  chown "$target_user":staff "$tmp"
  chmod 0644 "$tmp"
  mv "$tmp" "$agent"
  chown -R "$target_user":staff "$log_dir"
  chmod 0700 "$log_dir"
  /bin/launchctl asuser "$target_uid" /bin/launchctl bootout "gui/$target_uid" "$agent" 2>/dev/null || true
  /bin/launchctl asuser "$target_uid" /bin/launchctl bootstrap "gui/$target_uid" "$agent"
}


cmd_setup() {
  [ $# -le 2 ] || die "setup takes optional HOUR and MINUTE"
  hour=${1:-9} minute=${2:-30}
  if [ "$(id -u)" -ne 0 ]; then
    target_user=$(id -un)
    target_uid=$(id -u)
    exec /usr/bin/sudo "$0" __setup "$target_user" "$target_uid" "$USER_HOME" "$hour" "$minute"
  fi
  die "setup must be started by a non-root user"
}


cmd_setup_internal() {
  [ "$(id -u)" -eq 0 ] || die "internal setup requires root"
  [ $# -eq 5 ] || die "invalid internal setup invocation"
  target_user=$1 target_uid=$2 target_home=$3 hour=$4 minute=$5
  install_runtime
  security_file=$(group_file security)
  if [ ! -f "$security_file" ]; then
    tmp=$(mktemp /tmp/brew-watchtower-group.XXXXXX) || exit 1
    printf '# type\ttoken\tmode\n' > "$tmp"
    install -o root -g wheel -m 0644 "$tmp" "$security_file"
    rm -f "$tmp"
  fi
  write_launchagent "$target_user" "$target_uid" "$target_home" security daily "" "$hour" "$minute"
  echo "Protected runtime installed. Security group scheduled daily at $(printf '%02d:%02d' "$hour" "$minute")."
}


cmd_schedule() {
  [ $# -eq 3 ] || die "schedule requires GROUP HOUR MINUTE"
  require_mutable_groups
  group=$1 hour=$2 minute=$3
  valid_group "$group" || die "invalid group name: $group"
  [ -f "$(group_file "$group")" ] || die "unknown group: $group"
  if [ "$(id -u)" -ne 0 ]; then
    target_user=$(id -un)
    target_uid=$(id -u)
    exec /usr/bin/sudo "$POLICY_ROOT/bin/autoupdate" __schedule "$target_user" "$target_uid" "$USER_HOME" "$group" "$hour" "$minute"
  fi
  die "schedule must be started by a non-root user"
}


cmd_schedule_internal() {
  [ "$(id -u)" -eq 0 ] || die "internal scheduling requires root"
  [ $# -eq 6 ] || die "invalid internal schedule invocation"
  write_launchagent "$1" "$2" "$3" "$4" daily "" "$5" "$6"
  echo "Scheduled $4 daily at $(printf '%02d:%02d' "$5" "$6")."
}
