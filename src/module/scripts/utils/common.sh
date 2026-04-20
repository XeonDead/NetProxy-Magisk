#!/system/bin/sh
# Generic helper function

#######################################
# Write to standard log
#######################################
log() {
  local level="INFO"
  local message="$1"

  if [ $# -ge 2 ]; then
    level="$1"
    message="$2"
  fi

  local timestamp log_content
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  log_content="[$timestamp] [$level] $message"

  [ -n "${LOG_FILE:-}" ] && echo "$log_content" >> "$LOG_FILE"
  echo "$log_content" >&2
}

#######################################
# Log errors and exit
#######################################
die() {
  log "ERROR" "$1"
  exit "${2:-1}"
}

#######################################
# Detection busybox path
#######################################
detect_busybox() {
  for path in "/data/adb/ksu/bin/busybox" "/data/adb/ap/bin/busybox" "/data/adb/magisk/busybox"; do
    if [ -f "$path" ]; then
      echo "$path"
      return 0
    fi
  done
  echo "busybox"
}

#######################################
# Remove double quotes from configuration values
#######################################
strip_quotes() {
  echo "${1//\"/}"
}

#######################################
# Read tags from outbound configuration
#######################################
detect_outbound_tag() {
  local config_file="$1"
  [ -f "$config_file" ] || return 1

  grep -m 1 -E '"tag"[[:space:]]*:' "$config_file" 2> /dev/null \
    | sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

#######################################
# Get the specified process PID
#######################################
get_pid() {
  local bin="$1"
  [ -z "$bin" ] && return 1

  pidof -s "$bin" 2> /dev/null || pgrep -f "^$bin" 2> /dev/null | head -1 || true
}

#######################################
# Get specified PID running time
#######################################
get_process_uptime() {
  local pid="$1"
  [ -z "$pid" ] || [ ! -d "/proc/$pid" ] && { echo 0; return 1; }

  local start_time now_ticks
  start_time="$(awk '{print $22}' "/proc/$pid/stat" 2> /dev/null || echo 0)"
  now_ticks="$(awk '{print int($1 * 100)}' /proc/uptime 2> /dev/null || echo 0)"

  if [ "$start_time" -gt 0 ] && [ "$now_ticks" -gt 0 ]; then
    echo "$(( (now_ticks - start_time) / 100 ))"
  else
    echo 0
  fi
}
