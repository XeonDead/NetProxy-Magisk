#!/system/bin/sh
# sing-box Outstation Switch Script
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
# Restart service to make configuration effective
#######################################
restart_service_if_allowed() {
  if [ "$SWITCH_ALLOW_RESTART" = "1" ]; then
    log "INFO" "Restarting sing-box Service to apply configuration..."
    LOG_STDERR=0 sh "$SERVICE_SCRIPT" restart || die "Restart sing-box Service failure"
  else
    log "WARN" "The current phase does not allow the application configuration by restarting"
    return 1
  fi
}

#######################################
# Toggle Node Configuration
#######################################
switch_config() {
  local config_file="$1"
  local target_tag

  require_file "$MODULE_CONF" "The module profile does not exist: $MODULE_CONF"
  require_file "$config_file" "Node Profile does not exist: $config_file"

  log "INFO" "========== Start Switch sing-box Node Configuration =========="
  log "INFO" "Target Node File: $config_file"

  set_conf "$MODULE_CONF" "CURRENT_CONFIG" "$(quote_conf "$config_file")"
  target_tag="$(detect_outbound_tag "$config_file" || true)"

  if ! is_service_running; then
    log "INFO" "sing-box Not running, new node configuration will take effect at next startup"
    log "INFO" "========== Node Configuration Switch Finished =========="
    return 0
  fi

  if [ -n "$target_tag" ]; then
    if api_select_proxy "$target_tag"; then
      log "INFO" "Switch to node via control interface: $target_tag"
      log "INFO" "========== Node Configuration Switch Finished =========="
      return 0
    fi
    log "INFO" "The current run example failed to load the target node or control interface switch to restart service"
  else
    log "INFO" "Could not read target node tag, ready to restart service"
  fi

  restart_service_if_allowed || {
    log "WARN" "This is only the end of the configuration until the next service resumes."
    return 1
  }

  log "INFO" "========== Node Configuration Switch Finished =========="
}

#######################################
# Switch Out Station Mode
#######################################
switch_mode() {
  local target_mode="$1"

  case "$target_mode" in
    rule | global | direct) ;;
    *)
      die "Unknown Mode: $target_mode"
      ;;
  esac

  require_file "$MODULE_CONF" "The module profile does not exist: $MODULE_CONF"

  log "INFO" "========== Start Switch sing-box Out of station mode: $target_mode =========="
  set_conf "$MODULE_CONF" "OUTBOUND_MODE" "$target_mode"

  if ! is_service_running; then
    log "INFO" "sing-box Not running, new exit mode will take effect at next start"
    log "INFO" "========== Exit mode switch complete =========="
    return 0
  fi

  if api_set_mode "$target_mode"; then
    log "INFO" "Switching out station mode through control interface"
    log "INFO" "========== Exit mode switch complete =========="
    return 0
  fi

  log "WARN" "Control interface switch mode failed, ready to restart service"
  restart_service_if_allowed || {
    log "WARN" "This only completes the permanence of the mode and waits for the next service restart to take effect"
    return 1
  }

  log "INFO" "========== Exit mode switch complete =========="
}

#######################################
# Show Help
#######################################
show_usage() {
  cat << EOF
Usage: $(basename "$0") {config|mode} <Parameters>

Command:
  config <Profile>              Toggle Current Node Configuration
  mode <rule|global|direct>     Switch Out Station Mode
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
