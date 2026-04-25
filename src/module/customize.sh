#!/system/bin/sh
# NetProxy Magisk Module Install Script

SKIPUNZIP=1

################################################################################
# Constant definition
################################################################################

readonly MODULE_ID="netproxy"
readonly LIVE_DIR="/data/adb/modules/$MODULE_ID"
readonly CONFIG_DIR="$LIVE_DIR/config"
readonly BACKUP_DIR="$TMPDIR/netproxy_backup"
readonly LEGACY_CORE_NAME="x""ray"
readonly LEGACY_WEB_DIR_NAME="web""root"

# Global state: Whether proxy service is running
PROXY_WAS_RUNNING=false

# Profile to keep/Contents (Compare to config/)
readonly PRESERVE_CONFIGS="
    module.conf
    tproxy/
    singbox/
"

# Files need to set executables
readonly EXECUTABLE_FILES="
    bin/sing-box
    bin/proxylink
    bin/IPSET-LKM/ko-loader
    bin/IPSET-LKM/ipset
    action.sh
    scripts/cli
    scripts/core/service.sh
    scripts/core/switch.sh
    scripts/network/tproxy.sh
    scripts/core/subscription.sh
    scripts/utils/ipset.sh
    scripts/utils/gms_fix.sh
"

################################################################################
# Tool Functions
################################################################################

# Print the title of the separator
print_title() {
  ui_print ""
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print "  $1"
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Print Step
print_step() {
  ui_print "▶ $1"
}

# Print Successful
print_ok() {
  ui_print "  ✓ $1"
}

# Print Warning
print_warn() {
  ui_print "  ⚠ $1"
}

# Print Error
print_error() {
  ui_print "  ✗ $1"
}

# Check if the directory is not empty
dir_not_empty() {
  [ -d "$1" ] && [ "$(ls -A "$1" 2> /dev/null)" ]
}

################################################################################
# Core Functions
################################################################################

# Backup Existing Configuration
backup_config() {
  print_step "Check existing configuration..."

  if ! dir_not_empty "$CONFIG_DIR"; then
    print_ok "New installation, no backup required"
    return 0
  fi

  print_step "Backup Existing Configuration..."
  mkdir -p "$BACKUP_DIR"

  local config_item
  for config_item in $PRESERVE_CONFIGS; do
    local src="$CONFIG_DIR/$config_item"
    local dst="$BACKUP_DIR/$config_item"

    if [ -e "$src" ]; then
      mkdir -p "$(dirname "$dst")"
      if cp -r "$src" "$dst" 2> /dev/null; then
        print_ok "Backuped: $config_item"
      else
        print_warn "Backup failed: $config_item"
      fi
    fi
  done

  return 0
}

# Depress module files
extract_module() {
  print_step "Depress module files..."

  # Discharge to install temporary directory, exclude META-INF Contents
  if ! unzip -o "$ZIPFILE" -x "META-INF/*" -d "$MODPATH" > /dev/null 2>&1; then
    print_error "Unpressure failed."
    return 1
  fi

  print_ok "Module file unpressured"
  return 0
}

# Restore Profile
restore_config() {
  if ! dir_not_empty "$BACKUP_DIR"; then
    return 0
  fi

  print_step "Restore Profile..."

  local config_item
  for config_item in $PRESERVE_CONFIGS; do
    local src="$BACKUP_DIR/$config_item"
    local dst="$MODPATH/config/$config_item"

    if [ -e "$src" ]; then
      # Create Parent Directory
      mkdir -p "$(dirname "$dst")"
      # Delete Target (Prevent Directory Embedded)
      rm -rf "$dst" 2> /dev/null
      # Copy
      if cp -r "$src" "$dst" 2> /dev/null; then
        print_ok "Restored: $config_item"
      else
        print_warn "Recovery Failed: $config_item"
      fi
    fi
  done

  return 0
}

# Stop proxy service (If running)
stop_proxy_if_running() {
  # If... LIVE_DIR It doesn't exist. It doesn't have to stop.
  if [ ! -d "$LIVE_DIR" ]; then
    return 0
  fi

  if pidof -s "$LIVE_DIR/bin/sing-box" > /dev/null 2>&1 || pidof -s "$LIVE_DIR/bin/$LEGACY_CORE_NAME" > /dev/null 2>&1; then
    PROXY_WAS_RUNNING=true
    print_step "Proxy detected running and discontinued..."
    sh "$LIVE_DIR/scripts/core/service.sh" stop > /dev/null 2>&1
    print_ok "Service stopped"
  fi

  return 0
}

# Synchronize to Runtime Directory (Hot Update Support)
sync_to_live() {
  print_step "Synchronize to Runtime Directory..."

  # If... LIVE_DIR Cannot initialise Evolution's mail component.
  if [ ! -d "$LIVE_DIR" ]; then
    print_ok "First install, skip sync"
    return 0
  fi


  # Synchronize application files and scripts
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

  # Synchronise configuration of new files in directory (Increment Update)
  if [ -d "$MODPATH/config" ]; then
    print_step "incremental update configuration..."

    # Copy the new profile (Do Not Overwrite Existing)
    cp -rn "$MODPATH/config/"* "$LIVE_DIR/config/" 2> /dev/null
    print_ok "Configure directory updated incrementally"
  fi

  return 0
}

# Restart proxy services (If you're running before)
restart_proxy_if_needed() {
  if [ "$PROXY_WAS_RUNNING" = true ]; then
    print_step "Restart proxy services..."
    sh "$LIVE_DIR/scripts/core/service.sh" start > /dev/null 2>&1
    print_ok "Service started."
  fi

  return 0
}

# Set File Permissions
set_permissions() {
  print_step "Set File Permissions..."

  local file
  for file in $EXECUTABLE_FILES; do
    local path="$MODPATH/$file"
    if [ -e "$path" ]; then
      chmod 0755 "$path" 2> /dev/null
      # Synchronizes permissions in the directory when running
      [ -e "$LIVE_DIR/$file" ] && chmod 0755 "$LIVE_DIR/$file" 2> /dev/null
    fi
  done

  # Set Directory Permissions
  set_perm_recursive "$MODPATH" 0 0 0755 0755

  print_ok "Permission Settings Completed"
  return 0
}

# Ask the user whether to install the app
ask_install_app() {
  ui_print ""
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print "  Whether to install NetProxy Auxiliary application?"
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print ""
  ui_print "  [Volume+] Install (Open Google Play)"
  ui_print "  [Volume-] Skip"
  ui_print ""

  local timeout=10
  local choice=""

  while [ $timeout -gt 0 ]; do
    # Read Volume Keys
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
    print_ok "Open Google Play"
  else
    print_step "Skipped installation"
  fi

  return 0
}

# Integration IPSET LKM Driver Install
install_ipset_lkm() {
  print_title "Integration IPSET Driver Install"

  # If the installation package does not contain IPSET Component, skip the entire process
  if [ ! -d "$MODPATH/bin/IPSET-LKM" ] && [ ! -f "$MODPATH/bin/ipset" ]; then
      print_ok "Install package not included IPSET Component, Skip"
      return 0
  fi

  local skip_lkm=false

  # 1. Check if the kernel is built up. IP_SET Support
  print_step "Checking system IPSET Status..."
  if [ -f /proc/config.gz ] && zcat /proc/config.gz | grep -q "CONFIG_IP_SET=y"; then
      skip_lkm=true
  fi

  if [ "$skip_lkm" = "true" ]; then
      if command -v ipset >/dev/null 2>&1; then
          print_ok "The kernel support and tools are complete and need not be installed."
          # Clean-up of space against occupancy
          rm -rf "$MODPATH/bin/IPSET-LKM/netfilter"
          return 0
      else
          print_ok "The kernel has built-in support and only binary tools will be installed."
      fi
  fi

  # 2. Test kernel versions and select drivers
  if [ "$skip_lkm" = "false" ]; then
      local kernel_ver=$(uname -r | cut -d. -f1,2)
      print_step "kernel version detected: $kernel_ver"

      local src=""
      case "$kernel_ver" in
          5.10) src="5.10" ;;
          5.15) src="5.15" ;;
          6.1)  src="6.1" ;;
          6.6)  src="6.6" ;;
          6.12) src="6.12" ;;
          *) 
              print_warn "Unsupported kernel version: $kernel_ver"
              print_warn "Skip IPSET Driver Install"
              skip_lkm=true
              ;;
      esac

      if [ "$skip_lkm" = "false" ]; then
          local driver_source="$MODPATH/bin/IPSET-LKM/netfilter/$src"
          if [ -d "$driver_source" ]; then
              print_step "Installing for kernel $src Drivers..."
              rm -rf "/data/adb/netfilter"
              mkdir -p "/data/adb/netfilter"
              if cp -rf "$driver_source/"* "/data/adb/netfilter/" 2> /dev/null; then
                  set_perm_recursive "/data/adb/netfilter" 0 0 0755 0755
                  print_ok "IPSET LKM Driver deployed /data/adb/netfilter"
              else
                  print_error "Driver deployment failed"
              fi
          else
              print_warn "Lack of kernel in module $src Drivers"
          fi
      fi
  fi

  # 3. Configure IPSET Binary Tool Environment
  if [ -f "$MODPATH/bin/ipset" ]; then
      print_step "Configure IPSET Binary Tool Environment..."

      if [ "$KSU" ] || [ "$APATCH" ]; then
          print_ok "Detected KernelSU/APatch Environment"
          local ksu_bin="/data/adb/ksu/bin"
          [ "$APATCH" ] && ksu_bin="/data/adb/ap/bin"

          mkdir -p "$ksu_bin"
          rm -f "$ksu_bin/ipset"
          ln -s "/data/adb/modules/netproxy/bin/ipset" "$ksu_bin/ipset"
          print_ok "Created Symbolic Links: $ksu_bin/ipset"

      elif [ "$MAGISK_VER_CODE" ]; then
          print_ok "Detected Magisk Environment"
          mkdir -p "$MODPATH/system/bin"
          cp -f "$MODPATH/bin/ipset" "$MODPATH/system/bin/ipset"
          set_perm "$MODPATH/system/bin/ipset" 0 0 0755
          print_ok "ipset Mounted to /system/bin"
      fi
  fi

  # 4. Clean the driver source to reduce the size of the module
  rm -rf "$MODPATH/bin/IPSET-LKM/netfilter"

  return 0
}

# Clear temporary files
cleanup() {
  rm -rf "$BACKUP_DIR" 2> /dev/null
}

################################################################################
# Main Process
################################################################################

print_title "NetProxy - sing-box Transparent Agent"
ui_print "  Version: $(grep_prop version "$TMPDIR/module.prop" 2> /dev/null || echo "Unknown")"

# Depressure. module.prop Read Version
unzip -o "$ZIPFILE" "module.prop" -d "$TMPDIR" > /dev/null 2>&1

# Execute installation steps
if backup_config \
  && extract_module \
  && restore_config \
  && stop_proxy_if_running \
  && install_ipset_lkm \
  && sync_to_live \
  && set_permissions \
  && restart_proxy_if_needed; then

  cleanup

  print_title "Installation complete. Please restart the device."

  # Ask whether to install a companion application
  ask_install_app
else
  cleanup
  print_title "Installation Failed"
  ui_print ""
  ui_print "  Check the above-mentioned error information."
  ui_print "  And GitHub Issues Feedback"
  ui_print ""
  exit 1
fi
