#!/system/bin/sh
# NetProxy sing-box Service management script
# usage: service.sh {start|stop|restart|status}

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
# Check the service operating environment
#######################################
verify_environment() {
  require_file "$SING_BOX_BIN" "sing-box binary does not exist: $SING_BOX_BIN"
  require_file "$MODULE_CONF" "Module configuration file does not exist: $MODULE_CONF"
  require_file "$TPROXY_CONF_DIR/tproxy.conf" "Transparent proxy configuration file does not exist: $TPROXY_CONF_DIR/tproxy.conf"
  require_dir "$SINGBOX_DIR" "sing-box Configuration directory does not exist: $SINGBOX_DIR"
  require_dir "$CONFDIR" "Common configuration directory does not exist: $CONFDIR"

  ensure_dir "$MODDIR/logs" "Unable to create log directory: $MODDIR/logs"
  ensure_dir "$RUNTIME_DIR" "Unable to create runtime directory: $RUNTIME_DIR"
}

#######################################
# Clean runtime files
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

  log "INFO" "========== Start booting sing-box Serve =========="
  verify_environment

  pid="$(get_pid "$SING_BOX_BIN")"
  if [ -n "$pid" ]; then
    log "WARN" "sing-box Already running (PID: $pid)"
    return 0
  fi

  initialize_runtime_context
  scan_runtime_nodes "$CUR_OUTBOUND_DIR"
  write_runtime_outbounds > /dev/null
  runtime_outbounds="$RUNTIME_OUTBOUNDS_FILE"

  [ "$RUNTIME_NODE_COUNT" -gt 0 ] || die "There is no loadable node configuration in the current node directory: $CUR_OUTBOUND_DIR"

  log "INFO" "Current node directory: $CUR_OUTBOUND_DIR"
  log "INFO" "routing mode: $CUR_OUTBOUND_MODE"
  log "INFO" "Select mode: $CUR_SELECTOR_MODE"
  log "INFO" "Node loaded: $RUNTIME_NODE_COUNT，Skip invalid nodes: $RUNTIME_SKIPPED_COUNT"

  # Construct final startup parameters
  set -- run -C "$CONFDIR"
  while IFS= read -r node_path; do
    [ -n "$node_path" ] || continue
    set -- "$@" -c "$node_path"
  done << EOF
$RUNTIME_NODE_PATHS
EOF
  set -- "$@" -c "$runtime_outbounds"

  log "INFO" "Starting sing-box process..."
  cd "$SINGBOX_DIR" || die "Unable to enter configuration directory: $SINGBOX_DIR"
  nohup "$BUSYBOX" setuidgid root:net_admin "$SING_BOX_BIN" "$@" > "$SINGBOX_LOG_FILE" 2>&1 &

  new_pid=$!
  sleep 1

  if kill -0 "$new_pid" 2> /dev/null; then
    log "INFO" "sing-box Started successfully (PID: $new_pid)"
  else
    die "sing-box Startup failed，Please check the logs: $SINGBOX_LOG_FILE"
  fi

  if api_wait_available 5 1; then
    LOG_STDERR=0 SWITCH_ALLOW_RESTART=0 sh "$SWITCH_SCRIPT" mode "$CUR_OUTBOUND_MODE" || log "WARN" "Run mode sync failed"
  else
    log "WARN" "Control interface is not ready，Error 500 (Server Error)!!1500.That’s an error.There was an error. Please try again later.That’s all we know."
  fi

  log "INFO" "Loading transparent proxy rules..."
  sh "$TPROXY_SCRIPT" start -d "$TPROXY_CONF_DIR" >> "$LOG_FILE" 2>&1 || die "Transparent proxy rules failed to load"

  log "INFO" "========== sing-box Service startup completed =========="
}

#######################################
# Stop service
#######################################
do_stop() {
  local pid count

  log "INFO" "========== start stop sing-box Serve =========="
  verify_environment

  log "INFO" "Cleaning up transparent proxy rules..."
  sh "$TPROXY_SCRIPT" stop -d "$TPROXY_CONF_DIR" >> "$LOG_FILE" 2>&1 || true

  pid="$(get_pid "$SING_BOX_BIN")"
  if [ -z "$pid" ]; then
    log "INFO" "No running found sing-box process"
    cleanup_runtime_files
    log "INFO" "========== sing-box Service stop complete =========="
    return 0
  fi

  log "INFO" "Stopping sing-box process (PID: $pid)..."

  if kill "$pid" 2> /dev/null; then
    count=0
    while kill -0 "$pid" 2> /dev/null && [ "$count" -lt "$KILL_TIMEOUT" ]; do
      sleep 1
      count=$((count + 1))
    done

    if kill -0 "$pid" 2> /dev/null; then
      log "WARN" "Process is not responding SIGTERM，Use instead SIGKILL"
      kill -9 "$pid" 2> /dev/null || true
    fi
  fi

  cleanup_runtime_files
  log "INFO" "sing-box Process has stopped"
  log "INFO" "========== sing-box Service stop complete =========="
}

#######################################
# Restart service
#######################################
do_restart() {
  log "INFO" "========== Start restarting sing-box Serve =========="
  do_stop
  sleep 1
  do_start
}

#######################################
# View status
#######################################
do_status() {
  local pid uptime

  pid="$(get_pid "$SING_BOX_BIN")"
  if [ -n "$pid" ]; then
    printf "sing-box Running (PID: %s)\n" "$pid"
    uptime="$(get_process_uptime "$pid")"
    if [ "$uptime" -gt 0 ]; then
      printf "running time: %s Second\n" "$uptime"
    fi
    return 0
  fi

  printf "sing-box Not running\n"
  return 1
}

#######################################
# show help
#######################################
show_usage() {
  cat << EOF
usage: $(basename "$0") {start|stop|restart|status}

Order:
  start     start up sing-box Serve
  stop      stop sing-box Serve
  restart   Restart sing-box Serve
  status    Check service status
EOF
}

#######################################
# main entrance
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
