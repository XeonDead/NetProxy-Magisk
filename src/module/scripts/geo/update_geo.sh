#!/system/bin/sh
# NetProxy GeoIP/GeoSite Verification & Auto-Update Script
# Verifies local files against remote SHA256 and auto-updates if mismatched
set -e
readonly MODDIR="/data/adb/modules/netproxy"
readonly LOG_FILE="$MODDIR/logs/service.log"
. "$MODDIR/scripts/utils/log.sh"
#######################################
# Convert string to lowercase (POSIX-compatible)
# @param $1: input string
# @return: lowercase string via stdout
#######################################
to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}
#######################################
# Configuration: GeoIP
#######################################
readonly GEOIP_FILE="$MODDIR/bin/geoip.dat"
readonly GEOIP_SHA_URL="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat.sha256sum"
readonly GEOIP_DL_URL="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat"
#######################################
# Configuration: GeoSite
#######################################
readonly GEOSITE_FILE="$MODDIR/bin/geosite.dat"
readonly GEOSITE_SHA_URL="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat.sha256sum"
readonly GEOSITE_DL_URL="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat"
#######################################
# Verify and update a single file
# @param $1: file path
# @param $2: remote sha256 url
# @param $3: remote download url
# @param $4: label for logging (e.g., "GeoIP")
# @return 0 if OK or updated, 1 if error
#######################################
verify_and_update_file() {
  local file="$1"
  local sha_url="$2"
  local dl_url="$3"
  local label="$4"
  
  log "INFO" "[$label] Starting verification..."
  
  # Check if local file exists
  if [ ! -f "$file" ]; then
    log "WARN" "[$label] File not found, downloading..."
    if ! curl -fsSL -o "$file" "$dl_url" 2>/dev/null; then
      log "ERROR" "[$label] Failed to download $dl_url"
      return 1
    fi
    chmod 0644 "$file" 2>/dev/null
    log "INFO" "[$label] File downloaded successfully"
    return 0
  fi
  
  # Calculate local SHA256
  local local_sha
  if ! local_sha=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1); then
    log "ERROR" "[$label] Failed to calculate local SHA256"
    return 1
  fi
  log "DEBUG" "[$label] Local SHA256: $local_sha"
  
  # Download remote checksum
  local tmp_sha="$MODDIR/tmp/check.sha256"
  mkdir -p "$MODDIR/tmp"
  
  log "INFO" "[$label] Fetching remote checksum..."
  if ! curl -fsSL -o "$tmp_sha" "$sha_url" 2>/dev/null; then
    log "ERROR" "[$label] Failed to download checksum from $sha_url"
    rm -f "$tmp_sha"
    return 1
  fi
  
  # Parse remote SHA256 (extract 64-char hex hash)
  local remote_sha
  remote_sha=$(grep -oE '^[a-f0-9]{64}' "$tmp_sha" 2>/dev/null | head -1)
  rm -f "$tmp_sha"
  
  if [ -z "$remote_sha" ]; then
    log "ERROR" "[$label] Failed to parse remote SHA256"
    return 1
  fi
  log "DEBUG" "[$label] Remote SHA256: $remote_sha"
  
  # Compare (case-insensitive, POSIX-compatible)
  local local_sha_lower remote_sha_lower
  local_sha_lower=$(to_lower "$local_sha")
  remote_sha_lower=$(to_lower "$remote_sha")
  
  if [ "$local_sha_lower" = "$remote_sha_lower" ]; then
    log "INFO" "[$label] ✓ Checksum verified, file is up to date"
    return 0
  else
    log "WARN" "[$label] ✗ Checksum mismatch, updating file..."
    log "WARN" "[$label] Expected: $remote_sha"
    log "WARN" "[$label] Got:      $local_sha"
    
    # Download new file to temp location first
    local tmp_file="$MODDIR/tmp/$(basename "$file").new"
    if ! curl -fsSL -o "$tmp_file" "$dl_url" 2>/dev/null; then
      log "ERROR" "[$label] Failed to download updated file from $dl_url"
      rm -f "$tmp_file"
      return 1
    fi
    
    # Verify downloaded file before replacing
    local new_sha new_sha_lower
    new_sha=$(sha256sum "$tmp_file" 2>/dev/null | cut -d' ' -f1)
    new_sha_lower=$(to_lower "$new_sha")
    
    if [ "$new_sha_lower" != "$remote_sha_lower" ]; then
      log "ERROR" "[$label] Downloaded file checksum mismatch, aborting replacement"
      rm -f "$tmp_file"
      return 1
    fi
    
    # Replace original file
    mv -f "$tmp_file" "$file" 2>/dev/null
    chmod 0644 "$file" 2>/dev/null
    log "INFO" "[$label] ✓ File updated successfully"
    return 0
  fi
}
#######################################
# Main execution
#######################################
main() {
  log "INFO" "========== GeoIP/GeoSite Verification Started =========="
  
  local result=0
  
  # Verify and update GeoIP
  if ! verify_and_update_file "$GEOIP_FILE" "$GEOIP_SHA_URL" "$GEOIP_DL_URL" "GeoIP"; then
    log "ERROR" "GeoIP verification/update failed"
    result=1
  fi
  
  # Verify and update GeoSite
  if ! verify_and_update_file "$GEOSITE_FILE" "$GEOSITE_SHA_URL" "$GEOSITE_DL_URL" "GeoSite"; then
    log "ERROR" "GeoSite verification/update failed"
    result=1
  fi
  
  if [ $result -eq 0 ]; then
    log "INFO" "========== Verification completed successfully =========="
  else
    log "INFO" "========== Verification completed with errors =========="
  fi
  
  # Cleanup temp directory
  rm -rf "$MODDIR/tmp" 2>/dev/null
  
  exit $result
}

# Run main function
main "$@"