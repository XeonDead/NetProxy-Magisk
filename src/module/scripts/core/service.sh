#!/system/bin/sh
# NetProxy sing-box Service Management Script
# Usage: service.sh {start|stop|restart|status}

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly SING_BOX_BIN="$MODDIR/bin/sing-box"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly TPROXY_CONF_DIR="$MODDIR/config/tproxy"
readonly SINGBOX_LOG_FILE="$MODDIR/logs/sing-box.log"
readonly SINGBOX_DIR="$MODDIR/config/singbox"
readonly CONFDIR="$SINGBOX_DIR/confdir"
readonly RUNTIME_DIR="$SINGBOX_DIR/runtime"
readonly SWITCH_SCRIPT="$MODDIR/scripts/core/switch.sh"
readonly TPROXY_SCRIPT="$MODDIR/scripts/network/tproxy.sh"
readonly KILL_TIMEOUT=5

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"
. "$MODDIR/scripts/utils/api.sh"
. "$MODDIR/scripts/utils/nodes.sh"
. "$MODDIR/scripts/core/runtime.sh"

export PATH="$MODDIR/bin:$PATH"

readonly BUSYBOX="$(detect_busybox)"

#######################################
# Check service operating environment
#######################################
verify_environment() {
  require_file "$SING_BOX_BIN" "sing-box Binary does not exist: $SING_BOX_BIN"
  require_file "$MODULE_CONF" "The module profile does not exist: $MODULE_CONF"
  require_file "$TPROXY_CONF_DIR/tproxy.conf" "Transparent proxy profile does not exist: $TPROXY_CONF_DIR/tproxy.conf"
  require_dir "$SINGBOX_DIR" "sing-box Profile directory does not exist: $SINGBOX_DIR"
  require_dir "$CONFDIR" "Common configuration directory does not exist: $CONFDIR"

  ensure_dir "$MODDIR/logs" "Cannot create log directory: $MODDIR/logs"
  ensure_dir "$RUNTIME_DIR" "Could not create run-time directory: $RUNTIME_DIR"
}

#######################################
# Clear running-time files
#######################################
cleanup_runtime_files() {
  rm -f "$RUNTIME_DIR/outbounds.json" 2> /dev/null || true
}

#######################################
# Start service
#######################################
do_start() {
  local pid runtime_outbounds new_pid
  local node_path

  log "INFO" "========== Start sing-box Services =========="
  verify_environment

  pid="$(get_pid "$SING_BOX_BIN")"
  if [ -n "$pid" ]; then
    log "WARN" "sing-box Running (PID: $pid)"
    return 0
  fi

  initialize_runtime_context
  scan_runtime_nodes "$CUR_OUTBOUND_DIR"
  write_runtime_outbounds > /dev/null
  runtime_outbounds="$RUNTIME_OUTBOUNDS_FILE"

  [ "$RUNTIME_NODE_COUNT" -gt 0 ] || die "The current node directory does not have a loaded node configuration: $CUR_OUTBOUND_DIR"

  log "INFO" "Current Node Directory: $CUR_OUTBOUND_DIR"
  log "INFO" "Route Mode: $CUR_OUTBOUND_MODE"
  log "INFO" "Selection Mode: $CUR_SELECTOR_MODE"
  log "INFO" "Loaded Node: $RUNTIME_NODE_COUNTSkip invalid nodes: $RUNTIME_SKIPPED_COUNT"

  # Construct Final Start Parameters
  set -- run -C "$CONFDIR"
  while IFS= read -r node_path; do
    [ -n "$node_path" ] || continue
    set -- "$@" -c "$node_path"
  done << EOF
$RUNTIME_NODE_PATHS
EOF
  set -- "$@" -c "$runtime_outbounds"

  log "INFO" "Starting sing-box Process..."
  cd "$SINGBOX_DIR" || die "Cannot enter configuration directory: $SINGBOX_DIR"
  nohup "$BUSYBOX" setuidgid root:net_admin "$SING_BOX_BIN" "$@" > "$SINGBOX_LOG_FILE" 2>&1 &

  new_pid=$!
  sleep 1

  if kill -0 "$new_pid" 2> /dev/null; then
    log "INFO" "sing-box Started successfully (PID: $new_pid)"
  else
    die "sing-box Launch failed. Check log: $SINGBOX_LOG_FILE"
  fi

  if api_wait_available 5 1; then
    LOG_STDERR=0 SWITCH_ALLOW_RESTART=0 sh "$SWITCH_SCRIPT" mode "$CUR_OUTBOUND_MODE" || log "WARN" "Synchronising mode failed"
  else
    log "WARN" "The control interface is not in place, this is not synchronized"
  fi

  log "INFO" "Loading Transparent Agent Rules..."
  sh "$TPROXY_SCRIPT" start -d "$TPROXY_CONF_DIR" >> "$LOG_FILE" 2>&1 || die "Failed to load Transparent Agent Rules"

  log "INFO" "========== sing-box Service start complete. =========="
}

#######################################
# Stop Service
#######################################
do_stop() {
  local pid count

  log "INFO" "========== Start Stop sing-box Services =========="
  verify_environment

  log "INFO" "Clearing Transparent Agent Rules..."
  sh "$TPROXY_SCRIPT" stop -d "$TPROXY_CONF_DIR" >> "$LOG_FILE" 2>&1 || true

  pid="$(get_pid "$SING_BOX_BIN")"
  if [ -z "$pid" ]; then
    log "INFO" "No running found sing-box Process"
    cleanup_runtime_files
    log "INFO" "========== sing-box Service stopped =========="
    return 0
  fi

  log "INFO" "Stopping sing-box Process (PID: $pid)..."

  if kill "$pid" 2> /dev/null; then
    count=0
    while kill -0 "$pid" 2> /dev/null && [ "$count" -lt "$KILL_TIMEOUT" ]; do
      sleep 1
      count=$((count + 1))
    done

    if kill -0 "$pid" 2> /dev/null; then
      log "WARN" "Process not responding SIGTERMChange SIGKILL"
      kill -9 "$pid" 2> /dev/null || true
    fi
  fi

  cleanup_runtime_files
  log "INFO" "sing-box Process stopped"
  log "INFO" "========== sing-box Service stopped =========="
}

#######################################
# Restart Service
#######################################
do_restart() {
  log "INFO" "========== Start restart sing-box Services =========="
  do_stop
  sleep 1
  do_start
}

#######################################
# View Status
#######################################
do_status() {
  local pid uptime

  pid="$(get_pid "$SING_BOX_BIN")"
  if [ -n "$pid" ]; then
    printf "sing-box Running (PID: %s)\n" "$pid"
    uptime="$(get_process_uptime "$pid")"
    if [ "$uptime" -gt 0 ]; then
      printf "Run Time: %s sec\n" "$uptime"
    fi
    return 0
  fi

  printf "sing-box Not Run\n"
  return 1
}

#######################################
# Show Help
#######################################
show_usage() {
  cat << EOF
Usage: $(basename "$0") {start|stop|restart|status}

Command:
  start     Start sing-box Services
  stop      Stop sing-box Services
  restart   Restart sing-box Services
  status    View service status
EOF
}

#######################################
# Main entrance
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
    -h | --help | help)
      show_usage
      ;;
    *)
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
