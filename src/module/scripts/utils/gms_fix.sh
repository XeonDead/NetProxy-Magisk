#!/system/bin/sh
set -e
set -u

#############################################################################
# Multi-model compatibility repair script（OnePlus ColorOS + red devil / ZTE）
# Function:
#   - OnePlus Android 16: clean up fw_INPUT / fw_OUTPUT Influence in the chain Google Play / GMS rules
#   - red devil / ZTE: clean up zte_fw_gms Influence in the chain Google Play / GMS rules
#############################################################################

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# Clean up the specified chain REJECT/DROP rule
# parameter:
#   $1 - iptables Order (iptables / ip6tables)
#   $2 - name
#######################################
remove_block_rules_from_chain() {
  local cmd="$1"
  local chain="$2"
  local table="filter"

  # Get all REJECT or DROP The line number of the rule（reverse order）
  local line_numbers
  line_numbers=$(
    $cmd -t "$table" -nvL "$chain" --line-numbers 2> /dev/null \
      | awk '/REJECT|DROP/ {print $1}' \
      | sort -rn
  )

  if [ -z "$line_numbers" ]; then
    log "INFO" "$cmd: $chain Not found in chain REJECT/DROP rule"
    return 0
  fi

  local count=0

  for line_num in $line_numbers; do
    if $cmd -t "$table" -D "$chain" "$line_num" 2> /dev/null; then
      log "INFO" "Deleted ($cmd) $chain No. $line_num OK REJECT/DROP rule"
      count=$((count + 1))
    else
      log "WARN" "Delete failed ($cmd) $chain No. $line_num OK"
    fi
  done

  log "INFO" "$cmd: $chain Chain deleted $count strip REJECT/DROP rule"
}

#######################################
# Detect and perform cleaning of corresponding models
#######################################
fix_by_device() {
  local has_iptables=0
  local has_ip6tables=0

  command -v iptables > /dev/null 2>&1 && has_iptables=1
  command -v ip6tables > /dev/null 2>&1 && has_ip6tables=1

  if [ "$has_iptables" -eq 0 ] && [ "$has_ip6tables" -eq 0 ]; then
    log "ERROR" "iptables and ip6tables None of the commands exist"
    return 1
  fi

  # Detection system characteristics（Via chain existence）
  local is_oneplus=0
  local is_redmagic=0

  if iptables -t filter -L zte_fw_gms >/dev/null 2>&1; then
    is_redmagic=1
  elif iptables -t filter -L fw_INPUT >/dev/null 2>&1; then
    is_oneplus=1
  fi

  # Try both by default（Clean the chain if it exists，avoid misjudgment）
  local oneplus_chains="fw_INPUT fw_OUTPUT"
  local redmagic_chains="zte_fw_gms"

  log "INFO" "Start detecting and repairing..."

  # red devil / ZTE Rule cleanup
  if [ "$is_redmagic" -eq 1 ]; then
    log "INFO" "red devil detected / ZTE feature，Start cleaning zte_fw_gms"
    for chain in $redmagic_chains; do
      [ "$has_iptables" -eq 1 ] && remove_block_rules_from_chain "iptables" "$chain"
      [ "$has_ip6tables" -eq 1 ] && remove_block_rules_from_chain "ip6tables" "$chain"
    done
  fi

  # OnePlus / ColorOS Rule cleanup
  if [ "$is_oneplus" -eq 1 ]; then
    log "INFO" "detected OnePlus/ColorOS feature，Start cleaning fw_INPUT/fw_OUTPUT"
    for chain in $oneplus_chains; do
      [ "$has_iptables" -eq 1 ] && remove_block_rules_from_chain "iptables" "$chain"
      [ "$has_ip6tables" -eq 1 ] && remove_block_rules_from_chain "ip6tables" "$chain"
    done
  fi

}

#######################################
# Main process
#######################################
log "INFO" "========== Multi-model compatibility fix：start（OnePlus + red devil） =========="

fix_by_device

log "INFO" "========== Multi-model compatibility fix：Finish =========="
