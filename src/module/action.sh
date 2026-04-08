#!/system/bin/sh
# NetProxy Action Script
# Used for the module action button in Magisk Manager (toggle start/stop)
readonly MODDIR="${0%/*}"
readonly SERVICE_SCRIPT="$MODDIR/scripts/core/service.sh"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly XRAY_BIN="$MODDIR/bin/xray"
. "$MODDIR/scripts/utils/log.sh"
#######################################
# Check if Xray is running
#######################################
is_xray_running() {
pidof -s "$XRAY_BIN" > /dev/null 2>&1
}
# Redirect all output to Manager
exec 2>&1
echo "==================================="
echo "       NetProxy Action Script      "
echo "==================================="
# Main execution flow
if is_xray_running; then
log "INFO" "Xray is running, preparing to stop service..."
sh "$SERVICE_SCRIPT" stop
echo "==================================="
echo " Result: NetProxy service stopped"
echo "==================================="
else
log "INFO" "Xray is not running, preparing to start service..."
sh "$SERVICE_SCRIPT" start
echo "==================================="
echo " Result: NetProxy service started"
echo "==================================="
fi
# Brief pause to ensure logs are fully displayed before exiting
sleep 1