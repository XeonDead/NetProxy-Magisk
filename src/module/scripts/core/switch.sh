#!/system/bin/sh
# sing-box Off-site toggle script
# Usage: switch.sh {config|mode} <Parameters>

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
# Judgement sing-box Whether to run
#######################################
is_service_running() {
  [ -n "$(get_pid "$SING_BOX_BIN")" ]
}

#######################################
# Restart service to effective configuration
#######################################
restart_service_if_allowed() {
  if [ "$SWITCH_ALLOW_RESTART" = "1" ]; then
    log "INFO" "Restarting sing-box Service to Apply Configuration..."
    LOG_STDERR=0 sh "$SERVICE_SCRIPT" restart || die "Restart sing-box Service failed"
  else
    log "WARN" "Application configuration by restart is not allowed at the current stage"
    return 1
  fi
}

#######################################
# Toggle Node Configuration
#######################################
switch_config() {
  local config_file="$1"
  local target_tag

  require_file "$MODULE_CONF" "Module Profile does not exist: $MODULE_CONF"
  require_file "$config_file" "Node Profile does not exist: $config_file"

  log "INFO" "========== Start Switching sing-box Node Configuration =========="
  log "INFO" "Target Node File: $config_file"

  set_conf "$MODULE_CONF" "CURRENT_CONFIG" "$(quote_conf "$config_file")"
  target_tag="$(detect_outbound_tag "$config_file" || true)"

  if ! is_service_running; then
    log "INFO" "sing-box Not running, new node configuration will be effective on next start"
    log "INFO" "========== Node configuration switch complete =========="
    return 0
  fi

  if [ -n "$target_tag" ]; then
    if api_select_proxy "$target_tag"; then
      log "INFO" "Switched to node via control interface: $target_tag"
      log "INFO" "========== Node configuration switch complete =========="
      return 0
    fi
    log "INFO" "The current operation case did not load the target node or the control interface switch failed to start the service again"
  else
    log "INFO" "Could not close temporary folder: %s"
  fi

  restart_service_if_allowed || {
    log "WARN" "This configuration is only sustainable until the next service restart takes effect"
    return 1
  }

  log "INFO" "========== Node configuration switch complete =========="
}

#######################################
# Toggle outbound mode
#######################################
switch_mode() {
  local target_mode="$1"

  case "$target_mode" in
    rule | global | direct) ;;
    *)
      die "Unknown mode: $target_mode"
      ;;
  esac

  require_file "$MODULE_CONF" "Module Profile does not exist: $MODULE_CONF"

  log "INFO" "========== Start Switching sing-box Outbound Mode: $target_mode =========="
  set_conf "$MODULE_CONF" "OUTBOUND_MODE" "$target_mode"

  if ! is_service_running; then
    log "INFO" "sing-box Not running, new exit mode will be effective on next startup"
    log "INFO" "========== Outstop mode switch complete =========="
    return 0
  fi

  if api_set_mode "$target_mode"; then
    log "INFO" "Switching out mode via control interface"
    log "INFO" "========== Outstop mode switch complete =========="
    return 0
  fi

  log "WARN" "Control interface switch mode failed to reset service"
  restart_service_if_allowed || {
    log "WARN" "Only model sustainability is completed this time, pending the next service restart."
    return 1
  }

  log "INFO" "========== Outstop mode switch complete =========="
}

#######################################
# Show help
#######################################
show_usage() {
  cat << EOF
Usage: $(basename "$0") {config|mode} <Parameters>

Command:
  config <Profile>              Toggle current node configuration
  mode <rule|global|direct>     Toggle outbound mode
EOF
}

#######################################
# Main entrance
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
