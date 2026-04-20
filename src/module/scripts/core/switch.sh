#!/system/bin/sh
# sing-box Outbound switching script
# usage: switch.sh {config|mode} <parameter>

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly CLASH_API="127.0.0.1:9999"
readonly CLASH_SECRET="singbox"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# show help
#######################################
show_usage() {
  cat << EOF
usage: $(basename "$0") {config|mode} <parameter>

Order:
  config <Configuration file>           Switch current node configuration
  mode <rule|global|direct>   Switch outbound operation mode
EOF
}

#######################################
# Update module configuration items
#######################################
set_module_value() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "$MODULE_CONF" 2> /dev/null; then
    sed -i "s|^${key}=.*|${key}=\"$value\"|" "$MODULE_CONF"
  else
    echo "${key}=\"$value\"" >> "$MODULE_CONF"
  fi
}

#######################################
# Convert module mode to control interface mode
#######################################
control_mode_for_module_mode() {
  case "$1" in
    global) echo "Global" ;;
    direct) echo "Direct" ;;
    rule) echo "Rule" ;;
    *) return 1 ;;
  esac
}

#######################################
# Switch selector nodes through the control interface
#######################################
apply_control_node() {
  local node_tag="$1"
  command -v curl > /dev/null 2>&1 || return 1

  curl -fsS -X PUT \
    -H "Authorization: Bearer $CLASH_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$node_tag\"}" \
    "http://$CLASH_API/proxies/Proxy" > /dev/null 2>&1
}

#######################################
# Switching operating mode via control interface
#######################################
apply_control_mode() {
  command -v curl > /dev/null 2>&1 || return 1

  local control_mode
  control_mode="$(control_mode_for_module_mode "$1")" || return 1

  curl -fsS -X PATCH \
    -H "Authorization: Bearer $CLASH_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"mode\":\"$control_mode\"}" \
    "http://$CLASH_API/configs" > /dev/null 2>&1
}

#######################################
# Switch node configuration
#######################################
switch_config() {
  local config_file="$1"

  [ -f "$config_file" ] || die "Configuration file does not exist: $config_file"

  log "INFO" "========== Switching sing-box Outbound configuration =========="
  log "INFO" "object file: $config_file"

  # Persistence of current node path
  set_module_value "CURRENT_CONFIG" "$config_file"

  # While the service is running，Try switching the selector node now
  local tag
  tag="$(detect_outbound_tag "$config_file")"

  if [ -n "$tag" ] && apply_control_node "$tag"; then
    log "INFO" "Switched agent group via control interface to: $tag"
  else
    log "INFO" "Control interface is unavailable（The service is not running or the node is not loaded），The configuration will take effect on the next startup"
  fi

  log "INFO" "========== sing-box Outbound configuration switch completed =========="
}

#######################################
# Switch outbound mode
#######################################
switch_mode() {
  local target_mode="$1"

  case "$target_mode" in
    rule | global | direct) ;;
    *)
      echo "mistake: Unknown mode: $target_mode"
      exit 1
      ;;
  esac

  log "INFO" "========== Switching sing-box outbound mode: $target_mode =========="

  # persistence target pattern
  set_module_value "OUTBOUND_MODE" "$target_mode"
  log "INFO" "Module configuration updated: outbound mode=$target_mode"

  # Switch modes immediately while the service is running
  if apply_control_mode "$target_mode"; then
    log "INFO" "The new mode has been applied via the control interface"
  else
    log "INFO" "Control interface call failed（Maybe the service is not running），Mode will take effect on next boot"
  fi

  log "INFO" "========== sing-box Outbound mode switching completed =========="
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
