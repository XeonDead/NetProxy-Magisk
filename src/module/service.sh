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
  # Set the default for startup service
  AUTO_START=1
  GMS_FIX=1

  if [ -f "$MODULE_CONF" ]; then
    . "$MODULE_CONF"
    log "INFO" "Module configuration loaded"
  else
    log "WARN" "Module profile does not exist, using default"
  fi
}

#######################################
# Waiting for system startup to complete
#######################################
wait_for_boot() {
  log "INFO" "Waiting for system startup to complete..."

  # Waiting for system startup.
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
  done
  log "INFO" "System launch complete."

  # Waiting for storage to mount complete
  while [ ! -d "/sdcard/Android" ]; do
    sleep 1
  done
  log "INFO" "Storage Mount Completed"
}

#######################################
# Implementation equipment-specific repair scripts
#######################################
check_device_specific() {
  # Implement device compatibility restoration on commission
  if [ "$GMS_FIX" = "1" ]; then
    log "INFO" "GMS Repairs were activated and the scripts were repaired"
    sh "$MODDIR/scripts/utils/gms_fix.sh"
  fi
}

# Ensure log directory exists
mkdir -p "$MODDIR/logs"

#######################################
# Recording environmental information
#######################################
log_env_info() {
  log "INFO" "========== Environmental information testing =========="

  # KernelSU Environment
  if [ "$KSU" = "true" ]; then
    log "INFO" "Environment: KernelSU"
    log "INFO" "KernelSU Version: ${KSU_VER:-Unknown}"
    log "INFO" "KernelSU Version Number: ${KSU_VER_CODE:-Unknown}"
    log "INFO" "KernelSU kernel version number: ${KSU_KERNEL_VER_CODE:-Unknown}"
  fi

  # APatch / KernelPatch Environment
  if [ "$APATCH" = "true" ] || [ "$KERNELPATCH" = "true" ]; then
    log "INFO" "Environment: APatch / KernelPatch"
    log "INFO" "APatch Version: ${APATCH_VER:-Unknown}"
    log "INFO" "APatch Version Number: ${APATCH_VER_CODE:-Unknown}"
    log "INFO" "kernel version: ${KERNEL_VERSION:-Unknown}"
    log "INFO" "KernelPatch Version: ${KERNELPATCH_VERSION:-Unknown}"
  fi

  # Magisk Environment
  if [ -n "$MAGISK_VER" ]; then
    log "INFO" "Environment: Magisk"
    log "INFO" "Magisk Version: $MAGISK_VER"
    log "INFO" "Magisk Version Number: $MAGISK_VER_CODE"
  fi

  # Module version information
  if [ -f "$MODDIR/module.prop" ]; then
    local version line
    line=$(grep "^version=" "$MODDIR/module.prop")
    version="${line#*=}"
    line=$(grep "^versionCode=" "$MODDIR/module.prop")
    local versionCode="${line#*=}"
    log "INFO" "Module Version: ${version:-Unknown}"
    log "INFO" "Module Version Number: ${versionCode:-Unknown}"
  fi

  log "INFO" "=================================="
}

# Main Process
log "INFO" "========== NetProxy Service start =========="
log_env_info
load_module_config
sh "$MODDIR/scripts/utils/ipset.sh" load

wait_for_boot

# Check if startup is enabled
if [ "$AUTO_START" = "1" ]; then
  log "INFO" "Start service...."
  sh "$MODDIR/scripts/core/service.sh" start
  log "INFO" "Service start complete."
else
  log "INFO" "Starter is disabled. Skip start."
fi

# Implementation of equipment compatibility repairs
check_device_specific

log "INFO" "========== Service start-up process completed =========="
