#!/system/bin/sh
# Generic helper function

#######################################
# Write to standard log
#######################################
log() {
  local level="INFO"
  local message="$1"
  local timestamp log_content

  if [ $# -ge 2 ]; then
    level="$1"
    message="$2"
  fi

  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  log_content="[$timestamp] [$level] $message"

  [ -n "${LOG_FILE:-}" ] && printf "%s\n" "$log_content" >> "$LOG_FILE"
  [ "${LOG_STDERR:-1}" = "0" ] || printf "%s\n" "$log_content" >&2
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
  local path

  for path in "/data/adb/ksu/bin/busybox" "/data/adb/ap/bin/busybox" "/data/adb/magisk/busybox"; do
    if [ -x "$path" ]; then
      printf "%s\n" "$path"
      return 0
    fi
  done

  printf "%s\n" "busybox"
}

#######################################
# Determine whether the command exists
#######################################
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

#######################################
# Check if the file exists
#######################################
require_file() {
  local file="$1"
  local message="${2:-File does not exist: $file}"

  [ -f "$file" ] || die "$message"
}

#######################################
# Check if directory exists
#######################################
require_dir() {
  local dir="$1"
  local message="${2:-Directory does not exist: $dir}"

  [ -d "$dir" ] || die "$message"
}

#######################################
# Create directory
#######################################
ensure_dir() {
  local dir="$1"
  local message="${2:-Unable to create directory: $dir}"

  [ -d "$dir" ] || mkdir -p "$dir" || die "$message"
}

#######################################
# escape JSON string
#######################################
json_escape() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

#######################################
# Get the specified process PID
#######################################
get_pid() {
  local bin="$1"

  [ -n "$bin" ] || return 1
  pidof -s "$bin" 2> /dev/null || pgrep -f "^$bin" 2> /dev/null | head -1 || true
}

#######################################
# Get specified PID running time
#######################################
get_process_uptime() {
  local pid="$1"
  local start_time now_ticks

  [ -n "$pid" ] || { printf "0\n"; return 1; }
  [ -d "/proc/$pid" ] || { printf "0\n"; return 1; }

  start_time="$(awk '{print $22}' "/proc/$pid/stat" 2> /dev/null || echo 0)"
  now_ticks="$(awk '{print int($1 * 100)}' /proc/uptime 2> /dev/null || echo 0)"

  if [ "$start_time" -gt 0 ] && [ "$now_ticks" -gt 0 ]; then
    printf "%s\n" "$(( (now_ticks - start_time) / 100 ))"
  else
    printf "0\n"
  fi
}

#######################################
# Main testing equipment IPv4 address
#######################################
detect_primary_ipv4() {
  ip route get 1.1.1.1 2> /dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1
}
