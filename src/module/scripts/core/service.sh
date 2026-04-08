#!/system/bin/sh
# NetProxy Service Management Script
# Usage: service.sh {start|stop|restart|status}

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly XRAY_BIN="$MODDIR/bin/xray"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly XRAY_LOG_FILE="$MODDIR/logs/xray.log"
readonly CONFDIR="$MODDIR/config/xray/confdir"
readonly OUTBOUNDS_DIR="$MODDIR/config/xray/outbounds"

readonly KILL_TIMEOUT=5

# Detect busybox path
detect_busybox() {
  for path in "/data/adb/ksu/bin/busybox" "/data/adb/ap/bin/busybox" "/data/adb/magisk/busybox"; do
    if [ -f "$path" ]; then
      echo "$path"
      return 0
    fi
  done
  echo "busybox"
}

readonly BUSYBOX="$(detect_busybox)"

# Import utility library
. "$MODDIR/scripts/utils/log.sh"

export PATH="$MODDIR/bin:$PATH"

#######################################
# Get Xray PID
#######################################
get_pid() {
  pidof -s "$XRAY_BIN" 2> /dev/null || true
}

#######################################
# Start service
#######################################
do_start() {
  log "INFO" "========== Starting Xray service =========="

  local running_pid=$(get_pid)
  if [ -n "$running_pid" ]; then
    log "WARN" "Xray is already running (PID: $running_pid)"
    return 0
  fi

  [ -f "$MODULE_CONF" ] || die "Module config file not found: $MODULE_CONF"
  . "$MODULE_CONF"

  local outbound_config="${CURRENT_CONFIG:-}"
  outbound_config="${outbound_config//\"/}"
  [ -n "$outbound_config" ] || die "Failed to parse outbound config path"

  local outbound_mode="${OUTBOUND_MODE:-rule}"
  log "INFO" "Current outbound mode: $outbound_mode"

  # Determine routing config
  local routing_config="$CONFDIR/routing/rule.json"
  if [ "$outbound_mode" = "global" ]; then
    routing_config="$CONFDIR/routing/global.json"
    log "INFO" "Global mode: using global.json"
  elif [ "$outbound_mode" = "direct" ]; then
    routing_config="$CONFDIR/routing/direct.json"
    log "INFO" "Direct mode: using direct.json"
  fi

  [ -f "$routing_config" ] || die "Routing config file not found: $routing_config"
  [ -f "$outbound_config" ] || die "Outbound config file not found: $outbound_config"
  [ -d "$CONFDIR" ] || die "confdir directory not found: $CONFDIR"

  log "INFO" "Config directory: $CONFDIR"
  log "INFO" "Routing config: $routing_config"
  log "INFO" "Outbound config: $outbound_config"

  # Start Xray (root:net_admin)
  nohup "$BUSYBOX" setuidgid root:net_admin "$XRAY_BIN" run \
    -confdir "$CONFDIR" \
    -config "$routing_config" \
    -config "$outbound_config" \
    > "$XRAY_LOG_FILE" 2>&1 &

  local xray_pid=$!
  log "INFO" "Xray process started, PID: $xray_pid"

  # Wait for process to stabilize
  sleep 1

  if ! kill -0 "$xray_pid" 2> /dev/null; then
    die "Xray process failed to start, please check configuration"
  fi

  # Enable TProxy rules
  "$MODDIR/scripts/network/tproxy.sh" start -d "$MODDIR/config/tproxy" >> "$LOG_FILE" 2>&1

  log "INFO" "========== Xray service started successfully =========="
}

#######################################
# Stop service
#######################################
do_stop() {
  log "INFO" "========== Stopping Xray service =========="

  # Clean up TProxy rules first (to avoid network loss)
  log "INFO" "Cleaning up TProxy rules..."
  "$MODDIR/scripts/network/tproxy.sh" stop -d "$MODDIR/config/tproxy" >> "$LOG_FILE" 2>&1

  # Terminate Xray process
  local pid
  pid=$(get_pid)

  if [ -z "$pid" ]; then
    log "INFO" "No running Xray process found"
  else
    log "INFO" "Terminating Xray process (PID: $pid)..."

    # Graceful termination
    if kill "$pid" 2> /dev/null; then
      local count=0
      while kill -0 "$pid" 2> /dev/null && [ "$count" -lt "$KILL_TIMEOUT" ]; do
        sleep 1
        count=$((count + 1))
      done

      # Force kill if still running
      if kill -0 "$pid" 2> /dev/null; then
        log "WARN" "Process not responding to SIGTERM, sending SIGKILL"
        kill -9 "$pid" 2> /dev/null || true
      fi
    fi

    log "INFO" "Xray process terminated"
  fi

  log "INFO" "========== Xray service stopped successfully =========="
}

#######################################
# Restart service
#######################################
do_restart() {
  log "INFO" "========== Restarting Xray service =========="
  do_stop
  sleep 1
  do_start
}

#######################################
# Check status
#######################################
do_status() {
  local pid
  pid=$(get_pid)

  if [ -n "$pid" ]; then
    echo "Xray is running (PID: $pid)"
    # Show uptime
    if [ -f "/proc/$pid/stat" ]; then
      local uptime_ticks start_time now_ticks
      start_time=$(awk '{print $22}' "/proc/$pid/stat" 2> /dev/null || echo 0)
      now_ticks=$(awk '{print int($1 * 100)}' /proc/uptime 2> /dev/null || echo 0)
      if [ "$start_time" -gt 0 ] && [ "$now_ticks" -gt 0 ]; then
        uptime_ticks=$((now_ticks - start_time))
        echo "Uptime: $((uptime_ticks / 100)) seconds"
      fi
    fi
    return 0
  else
    echo "Xray is not running"
    return 1
  fi
}

#######################################
# Show help
#######################################
show_usage() {
  cat << EOF
Usage: $(basename "$0") {start|stop|restart|status}

Commands:
  start    Start Xray service
  stop     Stop Xray service
  restart  Restart Xray service
  status   Check service status

Examples:
  $(basename "$0") start
  $(basename "$0") restart
EOF
}

#######################################
# Main entry point
#######################################
main() {
  case "${1:-}" in
    start)
      do_start
      ;;
    stop)
      do_stop
      ;;
    restart)
      do_restart
      ;;
    status)
      do_status
      ;;
    -h|--help|help)
      show_usage
      ;;
    *)
      show_usage
      exit 1
      ;;
  esac
}

main "$@"