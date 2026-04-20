#!/system/bin/sh
# NetProxy Module operation script
# Used for action buttons in the module manager

readonly MODDIR="${0%/*}"
readonly SERVICE_SCRIPT="$MODDIR/scripts/core/service.sh"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly SING_BOX_BIN="$MODDIR/bin/sing-box"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# examine sing-box Whether to run
#######################################
is_sing_box_running() {
  pidof -s "$SING_BOX_BIN" > /dev/null 2>&1
}

# Pass the output to the module manager for display
exec 2>&1

echo "==================================="
echo "        NetProxy Module operation         "
echo "==================================="

# Start or stop based on current status
if is_sing_box_running; then
  log "INFO" "detected sing-box Running，Prepare to perform stop operation..."
  sh "$SERVICE_SCRIPT" stop
  echo "==================================="
  echo " Operation result: NetProxy Service has stopped"
  echo "==================================="
else
  log "INFO" "detected sing-box Not running，Prepare to perform startup operations..."
  sh "$SERVICE_SCRIPT" start
  echo "==================================="
  echo " Operation result: NetProxy Service has started"
  echo "==================================="
fi

# Hibernate briefly to ensure that the log is displayed completely before exiting
sleep 1
