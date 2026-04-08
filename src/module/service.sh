#!/system/bin/sh
set -e
readonly MODDIR="${0%/*}"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly LOG_FILE="$MODDIR/logs/service.log"
. "$MODDIR/scripts/utils/log.sh"
#######################################
# Load module configuration
#######################################
load_module_config() {
# Default values
AUTO_START=1
ONEPLUS_A16_FIX=1
if [ -f "$MODULE_CONF" ]; then
. "$MODULE_CONF"
log "INFO" "Module configuration loaded"
else
log "WARN" "Module config file not found, using defaults"
fi
}
#######################################
# Wait for system boot to complete
#######################################
wait_for_boot() {
log "INFO" "Waiting for system boot to complete..."
# Wait for boot completion
while [ "$(getprop sys.boot_completed)" != "1" ]; do
sleep 1
done
log "INFO" "System boot completed"
# Wait for storage mounting
while [ ! -d "/sdcard/Android" ]; do
sleep 1
done
log "INFO" "Storage mounted successfully"
}
#######################################
# Execute device-specific fix scripts
#######################################
check_device_specific() {
# If OnePlus A16 fix is enabled, execute it directly
if [ "$ONEPLUS_A16_FIX" = "1" ]; then
log "INFO" "OnePlus A16 fix enabled, executing fix script"
sh "$MODDIR/scripts/utils/oneplus_a16_fix.sh"
fi
}
# Ensure log directory exists
mkdir -p "$MODDIR/logs"
#######################################
# Log environment information
#######################################
log_env_info() {
log "INFO" "========== Environment Information Detection =========="
# KernelSU
if [ "$KSU" = "true" ]; then
log "INFO" "Environment: KernelSU"
log "INFO" "KSU_VER: ${KSU_VER:-unknown}"
log "INFO" "KSU_VER_CODE: ${KSU_VER_CODE:-unknown}"
log "INFO" "KSU_KERNEL_VER_CODE: ${KSU_KERNEL_VER_CODE:-unknown}"
fi
# APatch
if [ "$APATCH" = "true" ] || [ "$KERNELPATCH" = "true" ]; then
log "INFO" "Environment: APatch / KernelPatch"
log "INFO" "APATCH_VER: ${APATCH_VER:-unknown}"
log "INFO" "APATCH_VER_CODE: ${APATCH_VER_CODE:-unknown}"
log "INFO" "KERNEL_VERSION: ${KERNEL_VERSION:-unknown}"
log "INFO" "KERNELPATCH_VERSION: ${KERNELPATCH_VERSION:-unknown}"
fi
# Magisk
if [ -n "$MAGISK_VER" ]; then
log "INFO" "Environment: Magisk"
log "INFO" "MAGISK_VER: $MAGISK_VER"
log "INFO" "MAGISK_VER_CODE: $MAGISK_VER_CODE"
fi
# Module Info
if [ -f "$MODDIR/module.prop" ]; then
local version=$(grep "^version=" "$MODDIR/module.prop" | cut -d= -f2)
local versionCode=$(grep "^versionCode=" "$MODDIR/module.prop" | cut -d= -f2)
log "INFO" "VERSION: ${version:-unknown}"
log "INFO" "VERSION_CODE: ${versionCode:-unknown}"
fi
log "INFO" "=================================="
}
# Main execution flow
log "INFO" "========== NetProxy Service Starting =========="
log_env_info
load_module_config
wait_for_boot
# Check if auto-start on boot is enabled
if [ "$AUTO_START" = "1" ]; then
log "INFO" "Starting service..."
sh "$MODDIR/scripts/core/service.sh" start
log "INFO" "Service started successfully"
else
log "INFO" "Auto-start on boot disabled, skipping launch"
fi
# Execute OnePlus A16 fix
check_device_specific
log "INFO" "========== Service startup process finished =========="