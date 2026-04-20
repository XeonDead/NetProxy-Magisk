#!/system/bin/sh
set -e

readonly MODDIR="${0%/*}"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly LOG_FILE="$MODDIR/logs/service.log"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# Load module configuration
#######################################
load_module_config() {
  # Set startup service defaults
  AUTO_START=1
  GMS_FIX=1

  if [ -f "$MODULE_CONF" ]; then
    . "$MODULE_CONF"
    log "INFO" "Module configuration loaded"
  else
    log "WARN" "Module configuration file does not exist，Use default value"
  fi
}

#######################################
# Wait for system startup to complete
#######################################
wait_for_boot() {
  log "INFO" "Wait for system startup to complete..."

  # Wait for system boot to complete
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
  done
  log "INFO" "System startup completed"

  # Wait for the storage mount to complete
  while [ ! -d "/sdcard/Android" ]; do
    sleep 1
  done
  log "INFO" "Storage mounting completed"
}

#######################################
# Execute device-specific repair scripts
#######################################
check_device_specific() {
  # Perform device compatibility fixes when enabled
  if [ "$GMS_FIX" = "1" ]; then
    log "INFO" "GMS Repair is enabled，Execute repair script"
    sh "$MODDIR/scripts/utils/gms_fix.sh"
  fi
}

# Make sure the log directory exists
mkdir -p "$MODDIR/logs"

#######################################
# Record environmental information
#######################################
log_env_info() {
  log "INFO" "========== Environmental information detection =========="

  # KernelSU environment
  if [ "$KSU" = "true" ]; then
    log "INFO" "environment: KernelSU"
    log "INFO" "KernelSU Version: ${KSU_VER:-unknown}"
    log "INFO" "KernelSU version number: ${KSU_VER_CODE:-unknown}"
    log "INFO" "KernelSU Kernel version number: ${KSU_KERNEL_VER_CODE:-unknown}"
  fi

  # APatch / KernelPatch environment
  if [ "$APATCH" = "true" ] || [ "$KERNELPATCH" = "true" ]; then
    log "INFO" "environment: APatch / KernelPatch"
    log "INFO" "APatch Version: ${APATCH_VER:-unknown}"
    log "INFO" "APatch version number: ${APATCH_VER_CODE:-unknown}"
    log "INFO" "Kernel version: ${KERNEL_VERSION:-unknown}"
    log "INFO" "KernelPatch Version: ${KERNELPATCH_VERSION:-unknown}"
  fi

  # Magisk environment
  if [ -n "$MAGISK_VER" ]; then
    log "INFO" "environment: Magisk"
    log "INFO" "Magisk Version: $MAGISK_VER"
    log "INFO" "Magisk version number: $MAGISK_VER_CODE"
  fi

  # Module version information
  if [ -f "$MODDIR/module.prop" ]; then
    local version line
    line=$(grep "^version=" "$MODDIR/module.prop")
    version="${line#*=}"
    line=$(grep "^versionCode=" "$MODDIR/module.prop")
    local versionCode="${line#*=}"
    log "INFO" "module version: ${version:-unknown}"
    log "INFO" "Module version number: ${versionCode:-unknown}"
  fi

  log "INFO" "=================================="
}

# Main process
log "INFO" "========== NetProxy Service start =========="
log_env_info
load_module_config
sh "$MODDIR/scripts/utils/ipset.sh" load

wait_for_boot

# Error 500 (Server Error)!!1500.That’s an error.There was an error. Please try again later.That’s all we know.
if [ "$AUTO_START" = "1" ]; then
  log "INFO" "Start the service..."
  sh "$MODDIR/scripts/core/service.sh" start
  log "INFO" "Service startup completed"
else
  log "INFO" "Auto-start is disabled，Skip startup"
fi

# Perform device compatibility fixes
check_device_specific

log "INFO" "========== The service startup process ends =========="
