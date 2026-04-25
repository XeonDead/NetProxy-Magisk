#!/system/bin/sh
set -e

readonly MODDIR="${0%/*}"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly LOG_FILE="$MODDIR/logs/service.log"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# Loading module configuration
#######################################
load_module_config() {
  # Set the startup service default
  AUTO_START=1
  GMS_FIX=1

  if [ -f "$MODULE_CONF" ]; then
    . "$MODULE_CONF"
    log "INFO" "Module Configuration Loaded"
  else
    log "WARN" "The module configuration file does not exist, using default values"
  fi
}

#######################################
# Waiting for the system to start.
#######################################
wait_for_boot() {
  log "INFO" "Waiting for the system to start...."

  # Waiting for the system to turn on.
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
  done
  log "INFO" "System startup complete."

  # Waiting for storage mount complete
  while [ ! -d "/sdcard/Android" ]; do
    sleep 1
  done
  log "INFO" "Storage mount complete"
}

#######################################
# Execute device-specific fix scripts
#######################################
check_device_specific() {
  # Execute device compatibility fix when enabled
  if [ "$GMS_FIX" = "1" ]; then
    log "INFO" "GMS Repair enabled. Fix script executed."
    sh "$MODDIR/scripts/utils/gms_fix.sh"
  fi
}

# Ensure that log directory exists
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
    log "INFO" "Module version number: ${versionCode:-Unknown}"
  fi

  log "INFO" "=================================="
}

# Main Process
log "INFO" "========== NetProxy Service start =========="
log_env_info
load_module_config
sh "$MODDIR/scripts/utils/ipset.sh" load

wait_for_boot

# Check whether to turn on the switchboard.
if [ "$AUTO_START" = "1" ]; then
  log "INFO" "Start service...."
  sh "$MODDIR/scripts/core/service.sh" start
  log "INFO" "Service start complete."
else
  log "INFO" "Startup is disabled. Skipping startup."
fi

# Execute equipment compatibility restoration
check_device_specific

log "INFO" "========== End of service start process =========="
