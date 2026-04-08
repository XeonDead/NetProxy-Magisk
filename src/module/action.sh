#!/system/bin/sh
# NetProxy Action Script
# Used for the module action button in Magisk Manager (toggle start/stop)
readonly MODDIR="${0%/*}"
readonly SERVICE_SCRIPT="$MODDIR/scripts/core/service.sh"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly XRAY_BIN="$MODDIR/bin/xray"
readonly VERIFY_GEOIP_SCRIPT="$MODDIR/scripts/geo/update_geo.sh"
readonly VERIFY_DLC_SCRIPT="$MODDIR/scripts/geo/update_dlc.sh"
. "$MODDIR/scripts/utils/log.sh"
#######################################
# Check if Xray is running
#######################################
is_xray_running() {
  pidof -s "$XRAY_BIN" > /dev/null 2>&1
}
#######################################
# Verify resources before starting Xray
#######################################
verify_resources_before_start() {
  log "INFO" "Running pre-start resource verification..."
  
  # Verify & update geoip/geosite
  if [ -f "$VERIFY_GEOIP_SCRIPT" ]; then
    log "INFO" "Checking GeoIP/GeoSite databases..."
    sh "$VERIFY_GEOIP_SCRIPT" || log "WARN" "GeoIP/GeoSite verification failed, continuing with existing files"
  else
    log "WARN" "verify-geoip.sh not found, skipping"
  fi
  
  # Verify & update dlc
  if [ -f "$VERIFY_DLC_SCRIPT" ]; then
    log "INFO" "Checking DLC database..."
    sh "$VERIFY_DLC_SCRIPT" || log "WARN" "DLC verification failed, continuing with existing file"
  else
    log "WARN" "verify-dlc.sh not found, skipping"
  fi
  
  log "INFO" "Resource verification completed"
}
#######################################
# Main execution flow
#######################################
# Redirect all output to Manager
exec 2>&1
echo "==================================="
echo "       NetProxy Action Script      "
echo "==================================="

if is_xray_running; then
  log "INFO" "Xray is running, preparing to stop service..."
  sh "$SERVICE_SCRIPT" stop
  echo "==================================="
  echo " Result: NetProxy service stopped"
  echo "==================================="
else
  log "INFO" "Xray is not running, preparing to start service..."
  
  # Verify databases before starting Xray
  verify_resources_before_start
  
  sh "$SERVICE_SCRIPT" start
  echo "==================================="
  echo " Result: NetProxy service started"
  echo "==================================="
fi

# Brief pause to ensure logs are fully displayed before exiting
sleep 1