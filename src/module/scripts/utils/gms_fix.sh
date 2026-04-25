#!/system/bin/sh
# Device compatibility fix script

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# Remove interception rules from the chain
#######################################
remove_block_rules_from_chain() {
  local cmd="$1"
  local chain="$2"
  local line_numbers line_num count=0

  line_numbers="$(
    $cmd -t filter -nvL "$chain" --line-numbers 2> /dev/null \
      | awk '/REJECT|DROP/ {print $1}' \
      | sort -rn
  )"

  if [ -z "$line_numbers" ]; then
    log "INFO" "$cmd: $chain Not found in the chain. REJECT or DROP Rules"
    return 0
  fi

  for line_num in $line_numbers; do
    if $cmd -t filter -D "$chain" "$line_num" 2> /dev/null; then
      count=$((count + 1))
      log "INFO" "Deleted $cmd $chain The first in the chain. $line_num Interception rules."
    else
      log "WARN" "Delete Failed: $cmd $chain Rule $line_num Rule"
    fi
  done

  log "INFO" "$cmd: $chain Chain removed $count Interception rules."
}

#######################################
# Execute equipment compatibility restoration
#######################################
fix_by_device() {
  local has_iptables=0
  local has_ip6tables=0
  local is_oneplus=0
  local is_redmagic=0
  local chain

  command_exists iptables && has_iptables=1
  command_exists ip6tables && has_ip6tables=1

  if [ "$has_iptables" -eq 0 ] && [ "$has_ip6tables" -eq 0 ]; then
    log "ERROR" "iptables and ip6tables None exists."
    return 1
  fi

  if iptables -t filter -L zte_fw_gms > /dev/null 2>&1; then
    is_redmagic=1
  elif iptables -t filter -L fw_INPUT > /dev/null 2>&1; then
    is_oneplus=1
  fi

  if [ "$is_redmagic" -eq 1 ]; then
    log "INFO" "The Red Demon has been detected. / ZTE Rule number, start cleaning. zte_fw_gms"
    [ "$has_iptables" -eq 1 ] && remove_block_rules_from_chain "iptables" "zte_fw_gms"
    [ "$has_ip6tables" -eq 1 ] && remove_block_rules_from_chain "ip6tables" "zte_fw_gms"
  fi

  if [ "$is_oneplus" -eq 1 ]; then
    log "INFO" "Detected OnePlus / ColorOS Rule number, start cleaning. fw_INPUT and fw_OUTPUT"
    for chain in fw_INPUT fw_OUTPUT; do
      [ "$has_iptables" -eq 1 ] && remove_block_rules_from_chain "iptables" "$chain"
      [ "$has_ip6tables" -eq 1 ] && remove_block_rules_from_chain "ip6tables" "$chain"
    done
  fi

  if [ "$is_redmagic" -eq 0 ] && [ "$is_oneplus" -eq 0 ]; then
    log "INFO" "Rules for equipment not detected for repair"
  fi
}

#######################################
# Show help
#######################################
show_usage() {
  cat << EOF
Usage: $(basename "$0") [run]

Command:
  run      Execute equipment compatibility restoration
EOF
}

#######################################
# Main entrance
#######################################
main() {
  case "${1:-run}" in
    run)
      log "INFO" "========== Start installation compatibility restoration =========="
      fix_by_device
      log "INFO" "========== Device compatibility repair completed =========="
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
