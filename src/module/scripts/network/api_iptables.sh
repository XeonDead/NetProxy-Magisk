#!/system/bin/sh
# NetProxy Local API Firewall Rules Script
# Restricts port 8080 access to root only on loopback interface
set -u
readonly MODDIR="/data/adb/modules/netproxy"
readonly LOG_FILE="$MODDIR/logs/service.log"
. "$MODDIR/scripts/utils/log.sh"

#######################################
# Apply iptables rule if not already present
# @param $1: chain name (e.g., OUTPUT)
# @param $2: action (-I for insert, -A for append)
# @param $3: match & target arguments
# @param $4: description for logging
#######################################
ensure_iptables_rule() {
  local chain="$1"
  local action="$2"
  local match_target="$3"
  local desc="$4"

  # Check if rule exists (iptables -C does NOT use -A/-I flags)
  if iptables -C "$chain" $match_target 2>/dev/null; then
    log "DEBUG" "Rule already exists: $desc"
    return 0
  fi

  log "INFO" "Applying iptables rule: $desc"
  if iptables "$action" "$chain" $match_target 2>/dev/null; then
    log "INFO" "Successfully applied: $desc"
  else
    log "ERROR" "Failed to apply iptables rule: $desc"
    return 1
  fi
}

#######################################
# Main execution
#######################################
main() {
  log "INFO" "========== Configuring Local API Access Rules =========="

  # 1. Allow root (UID 0) to access port 8080 on loopback
  # Must be inserted first (-I) to take precedence over the reject rule
  ensure_iptables_rule \
    "OUTPUT" \
    "-I" \
    "-o lo -p tcp --dport 8080 -m owner --uid-owner 0 -j ACCEPT" \
    "Allow root access to local API (port 8080)"

  # 2. Block all other processes from accessing port 8080 on loopback
  # Appended last (-A) as a fallback reject rule
  ensure_iptables_rule \
    "OUTPUT" \
    "-A" \
    "-o lo -p tcp --dport 8080 -j REJECT" \
    "Block non-root access to local API (port 8080)"

  log "INFO" "========== Local API Access Rules Applied =========="
}

main "$@"