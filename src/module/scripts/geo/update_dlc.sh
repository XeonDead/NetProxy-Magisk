#!/system/bin/sh
# NetProxy DLC (Domain List Community) Verification & Auto-Update Script
# Verifies local dlc.dat against remote SHA256 and auto-updates if mismatched
set -e
readonly MODDIR="/data/adb/modules/netproxy"
readonly LOG_FILE="$MODDIR/logs/service.log"
. "$MODDIR/scripts/utils/log.sh"
#######################################
# Configuration: DLC (Domain List Community)
#######################################
readonly DLC_FILE="$MODDIR/bin/dlc.dat"
readonly DLC_SHA_URL="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat.sha256sum"
readonly DLC_DL_URL="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
#######################################
# Convert string to lowercase (POSIX-compatible)
# @param $1: input string
# @return: lowercase string via stdout
#######################################
to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}
#######################################
# Verify and update DLC file
# @return 0 if OK or updated, 1 if error
#######################################
verify_and_update_dlc() {
  log "INFO" "[DLC] Starting verification..."
  
  # Check if local file exists
  if [ ! -f "$DLC_FILE" ]; then
    log "WARN" "[DLC] File not found, downloading..."
    if ! curl -fsSL -o "$DLC_FILE" "$DLC_DL_URL" 2>/dev/null; then
      log "ERROR" "[DLC] Failed to download $DLC_DL_URL"
      return 1
    fi
    chmod 0644 "$DLC_FILE" 2>/dev/null
    log "INFO" "[DLC] File downloaded successfully"
    return 0
  fi
  
  # Calculate local SHA256
  local local_sha
  if ! local_sha=$(sha256sum "$DLC_FILE" 2>/dev/null | cut -d' ' -f1); then
    log "ERROR" "[DLC] Failed to calculate local SHA256"
    return 1
  fi
  log "DEBUG" "[DLC] Local SHA256: $local_sha"
  
  # Download remote checksum
  local tmp_sha="$MODDIR/tmp/dlc_check.sha256"
  mkdir -p "$MODDIR/tmp"
  
  log "INFO" "[DLC] Fetching remote checksum..."
  if ! curl -fsSL -o "$tmp_sha" "$DLC_SHA_URL" 2>/dev/null; then
    log "ERROR" "[DLC] Failed to download checksum from $DLC_SHA_URL"
    rm -f "$tmp_sha"
    return 1
  fi
  
  # Parse remote SHA256 (extract 64-char hex hash)
  local remote_sha
  remote_sha=$(grep -oE '^[a-f0-9]{64}' "$tmp_sha" 2>/dev/null | head -1)
  rm -f "$tmp_sha"
  
  if [ -z "$remote_sha" ]; then
    log "ERROR" "[DLC] Failed to parse remote SHA256"
    return 1
  fi
  log "DEBUG" "[DLC] Remote SHA256: $remote_sha"
  
  # Compare (case-insensitive, POSIX-compatible)
  local local_sha_lower remote_sha_lower
  local_sha_lower=$(to_lower "$local_sha")
  remote_sha_lower=$(to_lower "$remote_sha")
  
  if [ "$local_sha_lower" = "$remote_sha_lower" ]; then
    log "INFO" "[DLC] ✓ Checksum verified, file is up to date"
    return 0
  else
    log "WARN" "[DLC] ✗ Checksum mismatch, updating file..."
    log "WARN" "[DLC] Expected: $remote_sha"
    log "WARN" "[DLC] Got:      $local_sha"
    
    # Download new file to temp location first
    local tmp_file="$MODDIR/tmp/dlc.dat.new"
    if ! curl -fsSL -o "$tmp_file" "$DLC_DL_URL" 2>/dev/null; then
      log "ERROR" "[DLC] Failed to download updated file from $DLC_DL_URL"
      rm -f "$tmp_file"
      return 1
    fi
    
    # Verify downloaded file before replacing
    local new_sha new_sha_lower
    new_sha=$(sha256sum "$tmp_file" 2>/dev/null | cut -d' ' -f1)
    new_sha_lower=$(to_lower "$new_sha")
    
    if [ "$new_sha_lower" != "$remote_sha_lower" ]; then
      log "ERROR" "[DLC] Downloaded file checksum mismatch, aborting replacement"
      rm -f "$tmp_file"
      return 1
    fi
    
    # Replace original file
    mv -f "$tmp_file" "$DLC_FILE" 2>/dev/null
    chmod 0644 "$DLC_FILE" 2>/dev/null
    log "INFO" "[DLC] ✓ File updated successfully"
    return 0
  fi
}
#######################################
# Main execution
#######################################
main() {
  log "INFO" "========== DLC Verification Started =========="
  
  if verify_and_update_dlc; then
    log "INFO" "========== Verification completed successfully =========="
    exit 0
  else
    log "INFO" "========== Verification completed with errors =========="
    exit 1
  fi
}

# Run main function
main "$@"