#!/system/bin/sh
# NetProxy Magisk Module Installation Script
SKIPUNZIP=1
################################################################################
# Constant Definitions
################################################################################
readonly MODULE_ID="netproxy"
readonly LIVE_DIR="/data/adb/modules/$MODULE_ID"
readonly CONFIG_DIR="$LIVE_DIR/config"
readonly BACKUP_DIR="$TMPDIR/netproxy_backup"
# Global state: Whether Xray is running
XRAY_WAS_RUNNING=false
# Configuration files/directories to preserve (relative to config/)
readonly PRESERVE_CONFIGS="
module.conf
tproxy/
xray/outbounds
xray/confdir/02_dns.json
xray/confdir/routing
"
# Files that need executable permissions
readonly EXECUTABLE_FILES="
bin/xray
bin/proxylink
action.sh
scripts/cli
scripts/core/service.sh
scripts/core/switch-config.sh
scripts/core/switch-mode.sh
scripts/network/tproxy.sh
scripts/config/subscription.sh
scripts/utils/update-xray.sh
scripts/utils/oneplus_a16_fix.sh
"
################################################################################
# Utility Functions
################################################################################
# Print a title with divider lines
print_title() {
  ui_print ""
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print "  $1"
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
# Print step message
print_step() {
  ui_print "▶ $1"
}
# Print success message
print_ok() {
  ui_print "  ✓ $1"
}
# Print warning message
print_warn() {
  ui_print "  ⚠ $1"
}
# Print error message
print_error() {
  ui_print "  ✗ $1"
}
# Check if a directory is non-empty
dir_not_empty() {
  [ -d "$1" ] && [ "$(ls -A "$1" 2> /dev/null)" ]
}
################################################################################
# Core Functions
################################################################################
# Backup existing configuration
backup_config() {
  print_step "Checking existing configuration..."
  if ! dir_not_empty "$CONFIG_DIR"; then
    print_ok "Clean install, no backup needed"
    return 0
  fi
  print_step "Backing up existing configuration..."
  mkdir -p "$BACKUP_DIR"
  local config_item
  for config_item in $PRESERVE_CONFIGS; do
    local src="$CONFIG_DIR/$config_item"
    local dst="$BACKUP_DIR/$config_item"
    if [ -e "$src" ]; then
      mkdir -p "$(dirname "$dst")"
      if cp -r "$src" "$dst" 2> /dev/null; then
        print_ok "Backed up: $config_item"
      else
        print_warn "Backup failed: $config_item"
      fi
    fi
  done
  return 0
}
# Extract module files
extract_module() {
  print_step "Extracting module files..."
  # Extract to $MODPATH (Magisk temp dir, will be copied to $LIVE_DIR on reboot), excluding META-INF directory
  if ! unzip -o "$ZIPFILE" -x "META-INF/*" -d "$MODPATH" > /dev/null 2>&1; then
    print_error "Extraction failed"
    return 1
  fi
  print_ok "Module files extracted"
  return 0
}
# Restore configuration files
restore_config() {
  if ! dir_not_empty "$BACKUP_DIR"; then
    return 0
  fi
  print_step "Restoring configuration files..."
  local config_item
  for config_item in $PRESERVE_CONFIGS; do
    local src="$BACKUP_DIR/$config_item"
    local dst="$MODPATH/config/$config_item"
    if [ -e "$src" ]; then
      # Create parent directory
      mkdir -p "$(dirname "$dst")"
      # Remove target (prevent directory nesting)
      rm -rf "$dst" 2> /dev/null
      # Copy
      if cp -r "$src" "$dst" 2> /dev/null; then
        print_ok "Restored: $config_item"
      else
        print_warn "Restoration failed: $config_item"
      fi
    fi
  done
  return 0
}
# Stop Xray service (if running)
stop_xray_if_running() {
  # If LIVE_DIR doesn't exist, no need to stop
  if [ ! -d "$LIVE_DIR" ]; then
    return 0
  fi
  if pidof -s "$LIVE_DIR/bin/xray" > /dev/null 2>&1; then
    XRAY_WAS_RUNNING=true
    print_step "Xray is running, stopping service..."
    sh "$LIVE_DIR/scripts/core/service.sh" stop > /dev/null 2>&1
    print_ok "Service stopped"
  fi
  return 0
}
# Sync to runtime directory (hot update support)
sync_to_live() {
  print_step "Syncing to runtime directory..."
  # If LIVE_DIR doesn't exist, skip sync on first install
  if [ ! -d "$LIVE_DIR" ]; then
    print_ok "First install, skipping sync"
    return 0
  fi

  if [ -e "$LIVE_DIR/webroot" ]; then
    rm -rf "$LIVE_DIR/webroot" 2> /dev/null
    print_ok "Old WebUI removed"
  fi

  # Sync non-config files (bin, scripts, etc.)
  local sync_dirs="bin scripts action.sh service.sh module.prop"
  for item in $sync_dirs; do
    local src="$MODPATH/$item"
    local dst="$LIVE_DIR/$item"
    if [ -e "$src" ]; then
      rm -rf "$dst" 2> /dev/null
      if cp -r "$src" "$dst" 2> /dev/null; then
        print_ok "Synced: $item"
      else
        print_warn "Sync failed: $item"
      fi
    fi
  done
  # Sync new files in config directory (incremental update)
  if [ -d "$MODPATH/config" ]; then
    print_step "Incrementally updating configuration..."
    # Copy new config files (do not overwrite existing ones)
    cp -rn "$MODPATH/config/"* "$LIVE_DIR/config/" 2> /dev/null
    print_ok "Config directory incrementally updated"
  fi
  return 0
}
# Restart Xray service (if it was running before)
restart_xray_if_needed() {
  if [ "$XRAY_WAS_RUNNING" = true ]; then
    print_step "Restarting Xray service..."
    sh "$LIVE_DIR/scripts/core/service.sh" start > /dev/null 2>&1
    print_ok "Service started"
  fi
  return 0
}
# Set file permissions
set_permissions() {
  print_step "Setting file permissions..."
  local file
  for file in $EXECUTABLE_FILES; do
    local path="$MODPATH/$file"
    if [ -e "$path" ]; then
      chmod 0755 "$path" 2> /dev/null
      # Also set permissions for LIVE_DIR
      [ -e "$LIVE_DIR/$file" ] && chmod 0755 "$LIVE_DIR/$file" 2> /dev/null
    fi
  done
  # Set directory permissions
  set_perm_recursive "$MODPATH" 0 0 0755 0755
  print_ok "Permissions set"
  return 0
}
# Ask user whether to install companion app
ask_install_app() {
  ui_print ""
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print "  Install NetProxy companion app?"
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print ""
  ui_print "  [Vol+] Install (open Google Play)"
  ui_print "  [Vol-] Skip"
  ui_print ""
  local timeout=10
  local choice=""
  while [ $timeout -gt 0 ]; do
    # Read volume key
    local key=$(getevent -lqc 1 2> /dev/null | grep -E "KEY_VOLUME(UP|DOWN)" | head -1)
    if echo "$key" | grep -q "VOLUMEUP"; then
      choice="install"
      break
    elif echo "$key" | grep -q "VOLUMEDOWN"; then
      choice="skip"
      break
    fi
    sleep 1
    timeout=$((timeout - 1))
  done
  if [ "$choice" = "install" ]; then
    print_step "Opening Google Play..."
    am start -a android.intent.action.VIEW -d "https://play.google.com/store/apps/details?id=com.fanjv.netproxy" > /dev/null 2>&1
    print_ok "Opened Google Play"
  else
    print_step "Installation skipped"
  fi
  return 0
}
# Clean up temporary files
cleanup() {
  rm -rf "$BACKUP_DIR" 2> /dev/null
}
################################################################################
# Main Flow
################################################################################
print_title "NetProxy - Xray Transparent Proxy"
ui_print "  Version: $(grep_prop version "$TMPDIR/module.prop" 2> /dev/null || echo "unknown")"
# Extract module.prop to read version
unzip -o "$ZIPFILE" "module.prop" -d "$TMPDIR" > /dev/null 2>&1
# Execute installation steps
if backup_config \
&& extract_module \
&& restore_config \
&& stop_xray_if_running \
&& sync_to_live \
&& set_permissions \
&& restart_xray_if_needed; then
  cleanup
  print_title "Installation complete, please reboot your device"
  # Ask whether to install companion app
  ask_install_app
else
  cleanup
  print_title "Installation failed"
  ui_print ""
  ui_print "  Please check the error messages above"
  ui_print "  And report on GitHub Issues"
  ui_print ""
  exit 1
fi