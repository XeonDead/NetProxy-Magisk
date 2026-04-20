#!/system/bin/sh
# NetProxy Magisk Module installation script

SKIPUNZIP=1

################################################################################
# constant definition
################################################################################

readonly MODULE_ID="netproxy"
readonly LIVE_DIR="/data/adb/modules/$MODULE_ID"
readonly CONFIG_DIR="$LIVE_DIR/config"
readonly BACKUP_DIR="$TMPDIR/netproxy_backup"
readonly LEGACY_CORE_NAME="x""ray"
readonly LEGACY_WEB_DIR_NAME="web""root"

# global state: Is the proxy service running?
PROXY_WAS_RUNNING=false

# Configuration files that need to be retained/Table of contents (relative to config/)
readonly PRESERVE_CONFIGS="
    module.conf
    tproxy/
    singbox/
"

# Files that require executable permissions
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
# Utility function
################################################################################

# Print separated titles
print_title() {
  ui_print ""
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print "  $1"
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Printing steps
print_step() {
  ui_print "▶ $1"
}

# Print successfully
print_ok() {
  ui_print "  ✓ $1"
}

# Print warning
print_warn() {
  ui_print "  ⚠ $1"
}

# printing error
print_error() {
  ui_print "  ✗ $1"
}

# Check if the directory is not empty
dir_not_empty() {
  [ -d "$1" ] && [ "$(ls -A "$1" 2> /dev/null)" ]
}

################################################################################
# core function
################################################################################

# Back up existing configuration
backup_config() {
  print_step "Check existing configuration..."

  if ! dir_not_empty "$CONFIG_DIR"; then
    print_ok "fresh install，No backup required"
    return 0
  fi

  print_step "Back up existing configuration..."
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

# Unzip module files
extract_module() {
  print_step "Unzip module files..."

  # Unzip to the installation temporary directory，exclude META-INF Table of contents
  if ! unzip -o "$ZIPFILE" -x "META-INF/*" -d "$MODPATH" > /dev/null 2>&1; then
    print_error "Decompression failed"
    return 1
  fi

  print_ok "Module file has been decompressed"
  return 0
}

# restore configuration file
restore_config() {
  if ! dir_not_empty "$BACKUP_DIR"; then
    return 0
  fi

  print_step "restore configuration file..."

  local config_item
  for config_item in $PRESERVE_CONFIGS; do
    local src="$BACKUP_DIR/$config_item"
    local dst="$MODPATH/config/$config_item"

    if [ -e "$src" ]; then
      # Create parent directory
      mkdir -p "$(dirname "$dst")"
      # Delete target (Prevent directory nesting)
      rm -rf "$dst" 2> /dev/null
      # copy
      if cp -r "$src" "$dst" 2> /dev/null; then
        print_ok "Restored: $config_item"
      else
        print_warn "Recovery failed: $config_item"
      fi
    fi
  done

  return 0
}

# Stop proxy service (If running)
stop_proxy_if_running() {
  # if LIVE_DIR does not exist，no need to stop
  if [ ! -d "$LIVE_DIR" ]; then
    return 0
  fi

  if pidof -s "$LIVE_DIR/bin/sing-box" > /dev/null 2>&1 || pidof -s "$LIVE_DIR/bin/$LEGACY_CORE_NAME" > /dev/null 2>&1; then
    PROXY_WAS_RUNNING=true
    print_step "Detected that proxy service is running，Stop service..."
    sh "$LIVE_DIR/scripts/core/service.sh" stop > /dev/null 2>&1
    print_ok "Service has stopped"
  fi

  return 0
}

# Sync to runtime directory (Hot update support)
sync_to_live() {
  print_step "Sync to runtime directory..."

  # if LIVE_DIR does not exist，No synchronization required for first time installation
  if [ ! -d "$LIVE_DIR" ]; then
    print_ok "First time installation，Skip sync"
    return 0
  fi


  # Synchronize program files and scripts
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

  # Synchronize new files in configuration directory (incremental update)
  if [ -d "$MODPATH/config" ]; then
    print_step "Incremental update configuration..."

    # Copy the new configuration file (Do not overwrite existing)
    cp -rn "$MODPATH/config/"* "$LIVE_DIR/config/" 2> /dev/null
    print_ok "Configuration directory has been incrementally updated"
  fi

  return 0
}

# Restart proxy service (If it was running before)
restart_proxy_if_needed() {
  if [ "$PROXY_WAS_RUNNING" = true ]; then
    print_step "Restart proxy service..."
    sh "$LIVE_DIR/scripts/core/service.sh" start > /dev/null 2>&1
    print_ok "Service has started"
  fi

  return 0
}

# Set file permissions
set_permissions() {
  print_step "Set file permissions..."

  local file
  for file in $EXECUTABLE_FILES; do
    local path="$MODPATH/$file"
    if [ -e "$path" ]; then
      chmod 0755 "$path" 2> /dev/null
      # Synchronously set permissions in the runtime directory
      [ -e "$LIVE_DIR/$file" ] && chmod 0755 "$LIVE_DIR/$file" 2> /dev/null
    fi
  done

  # Set directory permissions
  set_perm_recursive "$MODPATH" 0 0 0755 0755

  print_ok "Permission settings completed"
  return 0
}

# Ask the user whether to install the companion app
ask_install_app() {
  ui_print ""
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print "  Whether to install NetProxy Companion app？"
  ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  ui_print ""
  ui_print "  [volume+] Install (Open Google Play)"
  ui_print "  [volume-] jump over"
  ui_print ""

  local timeout=10
  local choice=""

  while [ $timeout -gt 0 ]; do
    # Read volume keys
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

# integrated IPSET LKM Driver installation
install_ipset_lkm() {
  print_title "integrated IPSET Driver installation"

  # If the installation package does not include IPSET components，Skip the entire process
  if [ ! -d "$MODPATH/bin/IPSET-LKM" ] && [ ! -f "$MODPATH/bin/ipset" ]; then
      print_ok "The installation package does not include IPSET components，jump over"
      return 0
  fi

  local skip_lkm=false

  # 1. Check if the kernel has built-in IP_SET support
  print_step "Checking system IPSET state..."
  if [ -f /proc/config.gz ] && zcat /proc/config.gz | grep -q "CONFIG_IP_SET=y"; then
      skip_lkm=true
  fi

  if [ "$skip_lkm" = "true" ]; then
      if command -v ipset >/dev/null 2>&1; then
          print_ok "Kernel support and tools are complete，No installation required。"
          # Clean up to prevent taking up space
          rm -rf "$MODPATH/bin/IPSET-LKM/netfilter"
          return 0
      else
          print_ok "The kernel has built-in support，Only binary tools will be installed。"
      fi
  fi

  # 2. Detect kernel version and select driver
  if [ "$skip_lkm" = "false" ]; then
      local kernel_ver=$(uname -r | cut -d. -f1,2)
      print_step "Kernel version detected: $kernel_ver"

      local src=""
      case "$kernel_ver" in
          5.10) src="5.10" ;;
          5.15) src="5.15" ;;
          6.1)  src="6.1" ;;
          6.6)  src="6.6" ;;
          6.12) src="6.12" ;;
          *) 
              print_warn "Unsupported kernel version: $kernel_ver"
              print_warn "will be skipped IPSET Driver installation"
              skip_lkm=true
              ;;
      esac

      if [ "$skip_lkm" = "false" ]; then
          local driver_source="$MODPATH/bin/IPSET-LKM/netfilter/$src"
          if [ -d "$driver_source" ]; then
              print_step "Installing for kernel $src driver..."
              rm -rf "/data/adb/netfilter"
              mkdir -p "/data/adb/netfilter"
              if cp -rf "$driver_source/"* "/data/adb/netfilter/" 2> /dev/null; then
                  set_perm_recursive "/data/adb/netfilter" 0 0 0755 0755
                  print_ok "IPSET LKM The driver has been deployed to /data/adb/netfilter"
              else
                  print_error "Driver deployment failed"
              fi
          else
              print_warn "Missing kernel in module $src driver file"
          fi
      fi
  fi

  # 3. Configuration IPSET Binary tool environment
  if [ -f "$MODPATH/bin/ipset" ]; then
      print_step "Configuration IPSET Binary tool environment..."

      if [ "$KSU" ] || [ "$APATCH" ]; then
          print_ok "detected KernelSU/APatch environment"
          local ksu_bin="/data/adb/ksu/bin"
          [ "$APATCH" ] && ksu_bin="/data/adb/ap/bin"

          mkdir -p "$ksu_bin"
          rm -f "$ksu_bin/ipset"
          ln -s "/data/adb/modules/netproxy/bin/ipset" "$ksu_bin/ipset"
          print_ok "Symbolic link created: $ksu_bin/ipset"

      elif [ "$MAGISK_VER_CODE" ]; then
          print_ok "detected Magisk environment"
          mkdir -p "$MODPATH/system/bin"
          cp -f "$MODPATH/bin/ipset" "$MODPATH/system/bin/ipset"
          set_perm "$MODPATH/system/bin/ipset" 0 0 0755
          print_ok "ipset Mounted to /system/bin"
      fi
  fi

  # 4. Clean driver source code to reduce module size
  rm -rf "$MODPATH/bin/IPSET-LKM/netfilter"

  return 0
}

# Clean temporary files
cleanup() {
  rm -rf "$BACKUP_DIR" 2> /dev/null
}

################################################################################
# Main process
################################################################################

print_title "NetProxy - sing-box transparent proxy"
ui_print "  Version: $(grep_prop version "$TMPDIR/module.prop" 2> /dev/null || echo "unknown")"

# Unzip module.prop read version
unzip -o "$ZIPFILE" "module.prop" -d "$TMPDIR" > /dev/null 2>&1

# Follow the installation steps
if backup_config \
  && extract_module \
  && restore_config \
  && stop_proxy_if_running \
  && install_ipset_lkm \
  && sync_to_live \
  && set_permissions \
  && restart_proxy_if_needed; then

  cleanup

  print_title "Installation completed，Please restart your device"

  # Ask whether to install companion app
  ask_install_app
else
  cleanup
  print_title "Installation failed"
  ui_print ""
  ui_print "  Please check the above error message"
  ui_print "  and in GitHub Issues feedback"
  ui_print ""
  exit 1
fi
