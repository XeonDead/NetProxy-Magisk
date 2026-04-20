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

readonly KILL_TIMEOUT=5

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/core/runtime.sh"

export PATH="$MODDIR/bin:$PATH"

readonly BUSYBOX="$(detect_busybox)"


#######################################
# Start service
#######################################
do_start() {
  log "INFO" "========== Start booting sing-box Serve =========="

  # Check current service status
  local pid
  pid="$(get_pid "$SING_BOX_BIN")"
  if [ -n "$pid" ]; then
    log "WARN" "sing-box Already running (PID: $pid)"
    return 0
  fi

  # Prepare startup environment and configuration
  initialize_runtime_context || exit 1
  write_runtime_outbounds || exit 1
  local runtime_outbounds="$RUNTIME_DIR/outbounds.json"

  log "INFO" "routing mode: $CUR_OUTBOUND_MODE"
  log "INFO" "node directory: $CUR_OUTBOUND_DIR"

  # Construct final startup parameters
  set -- run -C "$CONFDIR"
  [ -n "$runtime_outbounds" ] && set -- "$@" -c "$runtime_outbounds"
  eval "set -- \"\$@\" $SCAN_NODE_ARGS"

  [ "$SCAN_NODE_COUNT" -gt 0 ] || die "There is no loadable node configuration in the current node directory: $CUR_OUTBOUND_DIR"
  log "INFO" "Node loaded: $SCAN_NODE_COUNT，skip node: $SCAN_SKIPPED_COUNT"

  # start up sing-box process
  log "INFO" "Starting sing-box process..."
  cd "$SINGBOX_DIR" || die "Unable to enter configuration directory: $SINGBOX_DIR"
  nohup "$BUSYBOX" setuidgid root:net_admin "$SING_BOX_BIN" "$@" > "$SINGBOX_LOG_FILE" 2>&1 &
  
  local new_pid=$!
  sleep 1

  # Confirm that the process is running stably
  if kill -0 "$new_pid" 2> /dev/null; then
    log "INFO" "sing-box Started successfully (PID: $new_pid)"
  else
    die "sing-box Startup failed，Please check the logs: $SINGBOX_LOG_FILE"
  fi

  # Run mode synchronously and load transparent proxy rules
  sh "$MODDIR/scripts/core/switch.sh" mode "$CUR_OUTBOUND_MODE" >> "$LOG_FILE" 2>&1 || log "WARN" "Control interface failed"
  log "INFO" "Load transparent proxy rules..."
  "$MODDIR/scripts/network/tproxy.sh" start -d "$TPROXY_CONF_DIR" >> "$LOG_FILE" 2>&1

  log "INFO" "========== sing-box Service startup completed =========="
}

#######################################
# Stop service
#######################################
do_stop() {
  log "INFO" "========== start stop sing-box Serve =========="

  log "INFO" "clean up TProxy rule..."
  "$MODDIR/scripts/network/tproxy.sh" stop -d "$TPROXY_CONF_DIR" >> "$LOG_FILE" 2>&1 || true

  local pid
  pid="$(get_pid "$SING_BOX_BIN")"

  if [ -z "$pid" ]; then
    log "INFO" "No running found sing-box process"
  else
    log "INFO" "Terminating sing-box process (PID: $pid)..."

    if kill "$pid" 2> /dev/null; then
      local count=0
      while kill -0 "$pid" 2> /dev/null && [ "$count" -lt "$KILL_TIMEOUT" ]; do
        sleep 1
        count=$((count + 1))
      done

      if kill -0 "$pid" 2> /dev/null; then
        log "WARN" "Process is not responding SIGTERM，send SIGKILL"
        kill -9 "$pid" 2> /dev/null || true
      fi
    fi

    log "INFO" "sing-box process terminated"
  fi

  rm -f "$RUNTIME_DIR/outbounds.json" 2> /dev/null || true

  log "INFO" "========== sing-box Service stop complete =========="
}

#######################################
# Restart service
#######################################
do_restart() {
  log "INFO" "========== Restart sing-box Serve =========="
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
    echo "sing-box Running (PID: $pid)"
    uptime="$(get_process_uptime "$pid")"
    if [ "$uptime" -gt 0 ]; then
      echo "running time: ${uptime} Second"
    fi
    return 0
  else
    echo "sing-box Not running"
    return 1
  fi
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
