#!/system/bin/sh
# sing-box Outbound switching script
# usage: switch.sh {config|mode} <parameter>

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly SERVICE_SCRIPT="$MODDIR/scripts/core/service.sh"
readonly SING_BOX_BIN="$MODDIR/bin/sing-box"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly SWITCH_ALLOW_RESTART="${SWITCH_ALLOW_RESTART:-1}"

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"
. "$MODDIR/scripts/utils/api.sh"
. "$MODDIR/scripts/utils/nodes.sh"

#######################################
# judgment sing-box Is it running
#######################################
is_service_running() {
  [ -n "$(get_pid "$SING_BOX_BIN")" ]
}

#######################################
# Restart the service to make the configuration take effect
#######################################
restart_service_if_allowed() {
  if [ "$SWITCH_ALLOW_RESTART" = "1" ]; then
    log "INFO" "Restarting sing-box Service to apply configuration..."
    LOG_STDERR=0 sh "$SERVICE_SCRIPT" restart || die "Restart sing-box Service failed"
  else
    log "WARN" "Restarting the application configuration is not allowed at this stage"
    return 1
  fi
}

#######################################
# Switch node configuration
#######################################
switch_config() {
  local config_file="$1"
  local target_tag

  require_file "$MODULE_CONF" "Module configuration file does not exist: $MODULE_CONF"
  require_file "$config_file" "Node configuration file does not exist: $config_file"

  log "INFO" "========== Start switching sing-box Node configuration =========="
  log "INFO" "target node file: $config_file"

  set_conf "$MODULE_CONF" "CURRENT_CONFIG" "$(quote_conf "$config_file")"
  target_tag="$(detect_outbound_tag "$config_file" || true)"

  if ! is_service_running; then
    log "INFO" "sing-box Not running，The new node configuration will take effect on the next startup"
    log "INFO" "========== Node configuration switching completed =========="
    return 0
  fi

  if [ -n "$target_tag" ]; then
    if api_select_proxy "$target_tag"; then
      log "INFO" "Switched to node via control interface: $target_tag"
      log "INFO" "========== Node configuration switching completed =========="
      return 0
    fi
    log "INFO" "The current running instance does not load the target node or the control interface switching fails.，Prepare to restart service"
  else
    log "INFO" "Unable to read target node label，Prepare to restart service"
  fi

  restart_service_if_allowed || {
    log "WARN" "This time only configuration persistence is completed.，Wait for the next service restart to take effect."
    return 1
  }

  log "INFO" "========== Node configuration switching completed =========="
}

#######################################
# Switch outbound mode
#######################################
switch_mode() {
  local target_mode="$1"

  case "$target_mode" in
    rule | global | direct) ;;
    *)
      die "Unknown mode: $target_mode"
      ;;
  esac

  require_file "$MODULE_CONF" "Module configuration file does not exist: $MODULE_CONF"

  log "INFO" "========== Start switching sing-box outbound mode: $target_mode =========="
  set_conf "$MODULE_CONF" "OUTBOUND_MODE" "$target_mode"

  if ! is_service_running; then
    log "INFO" "sing-box Not running，The new outbound mode will take effect on the next boot"
    log "INFO" "========== Outbound mode switching completed =========="
    return 0
  fi

  if api_set_mode "$target_mode"; then
    log "INFO" "Switched outbound mode via control interface"
    log "INFO" "========== Outbound mode switching completed =========="
    return 0
  fi

  log "WARN" "Control interface switching mode failed，Prepare to restart service"
  restart_service_if_allowed || {
    log "WARN" "This time only the pattern persistence is completed.，Wait for the next service restart to take effect."
    return 1
  }

  log "INFO" "========== Outbound mode switching completed =========="
}

#######################################
# show help
#######################################
show_usage() {
  cat << EOF
usage: $(basename "$0") {config|mode} <parameter>

Order:
  config <Configuration file>              Switch current node configuration
  mode <rule|global|direct>     Switch outbound mode
EOF
}

#######################################
# main entrance
#######################################
main() {
  local command="${1:-}"
  local value="${2:-}"

  case "$command" in
    config)
      [ -n "$value" ] || { show_usage; exit 1; }
      switch_config "$value"
      ;;
    mode)
      [ -n "$value" ] || { show_usage; exit 1; }
      switch_mode "$value"
      ;;
    -h | --help | help | "")
      show_usage
      [ -n "$command" ] || exit 1
      ;;
    *)
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
