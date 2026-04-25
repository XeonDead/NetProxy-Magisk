#!/system/bin/sh
# sing-box Configure auxiliary functions when running

CUR_OUTBOUND_CONFIG=""
CUR_OUTBOUND_DIR=""
CUR_OUTBOUND_MODE=""
CUR_SELECTOR_MODE=""
CUR_CURRENT_TAG=""

RUNTIME_OUTBOUNDS_FILE=""
RUNTIME_NODE_PATHS=""
RUNTIME_NODE_TAGS_JSON=""
RUNTIME_NODE_COUNT=0
RUNTIME_SKIPPED_COUNT=0

#######################################
# Context at Initialising Run
#######################################
initialize_runtime_context() {
  require_file "${MODULE_CONF:-}" "Module Profile does not exist: ${MODULE_CONF:-Undefined}"
  require_dir "${SINGBOX_DIR:-}" "sing-box Configuration directory does not exist: ${SINGBOX_DIR:-Undefined}"
  require_dir "${CONFDIR:-}" "Universal Configuration Directory does not exist: ${CONFDIR:-Undefined}"
  require_dir "${RUNTIME_DIR:-}" "Cannot initialise Evolution's mail component.: ${RUNTIME_DIR:-Undefined}"

  CUR_OUTBOUND_CONFIG="$(read_conf "$MODULE_CONF" "CURRENT_CONFIG" "")"
  CUR_OUTBOUND_MODE="$(read_conf "$MODULE_CONF" "OUTBOUND_MODE" "rule")"
  CUR_SELECTOR_MODE="$(read_conf "$MODULE_CONF" "SELECTOR_MODE" "urltest")"

  [ -n "$CUR_OUTBOUND_CONFIG" ] || die "CURRENT_CONFIG Undefined, select nodes first"
  require_file "$CUR_OUTBOUND_CONFIG" "The current node profile does not exist: $CUR_OUTBOUND_CONFIG"

  CUR_OUTBOUND_DIR="${CUR_OUTBOUND_CONFIG%/*}"
  [ "$CUR_OUTBOUND_DIR" != "$CUR_OUTBOUND_CONFIG" ] || die "Could not close temporary folder: %s: $CUR_OUTBOUND_CONFIG"
  require_dir "$CUR_OUTBOUND_DIR" "The current node directory does not exist: $CUR_OUTBOUND_DIR"

  CUR_CURRENT_TAG="$(detect_outbound_tag "$CUR_OUTBOUND_CONFIG" || true)"
  [ -n "$CUR_CURRENT_TAG" ] || die "Could not read current node tab: $CUR_OUTBOUND_CONFIG"

  RUNTIME_OUTBOUNDS_FILE="$RUNTIME_DIR/outbounds.json"
}

#######################################
# Clear Node Cache on Airline
#######################################
reset_runtime_nodes() {
  RUNTIME_NODE_PATHS=""
  RUNTIME_NODE_TAGS_JSON=""
  RUNTIME_NODE_COUNT=0
  RUNTIME_SKIPPED_COUNT=0
}

#######################################
# Append running node cache
#######################################
append_runtime_node() {
  local file="$1"
  local tag="$2"
  local escaped_tag

  if [ -n "$RUNTIME_NODE_PATHS" ]; then
    RUNTIME_NODE_PATHS="${RUNTIME_NODE_PATHS}
$file"
  else
    RUNTIME_NODE_PATHS="$file"
  fi

  if ! is_reserved_outbound_tag "$tag"; then
    escaped_tag="$(json_escape "$tag")"
    if [ -n "$RUNTIME_NODE_TAGS_JSON" ]; then
      RUNTIME_NODE_TAGS_JSON="$RUNTIME_NODE_TAGS_JSON, \"$escaped_tag\""
    else
      RUNTIME_NODE_TAGS_JSON="\"$escaped_tag\""
    fi
  fi

  RUNTIME_NODE_COUNT=$((RUNTIME_NODE_COUNT + 1))
}

#######################################
# Scan the current node directory
#######################################
scan_runtime_nodes() {
  local current_dir="${1:-$CUR_OUTBOUND_DIR}"
  local file tag

  require_dir "$current_dir" "Node directory does not exist: $current_dir"
  reset_runtime_nodes

  for file in "$current_dir"/*.json; do
    is_node_config_file "$file" || continue
    tag="$(detect_outbound_tag "$file" || true)"

    if [ -z "$tag" ]; then
      RUNTIME_SKIPPED_COUNT=$((RUNTIME_SKIPPED_COUNT + 1))
      continue
    fi

    append_runtime_node "$file" "$tag"
  done
}

#######################################
# Generate outstation configuration when running
#######################################
write_runtime_outbounds() {
  local current_config="${1:-$CUR_OUTBOUND_CONFIG}"
  local selector_mode="${2:-$CUR_SELECTOR_MODE}"
  local tags="$RUNTIME_NODE_TAGS_JSON"

  [ -n "$current_config" ] || die "Current node configuration not initialized"
  [ -n "$selector_mode" ] || selector_mode="urltest"

  if [ "$RUNTIME_NODE_COUNT" -eq 0 ] && [ -z "$RUNTIME_NODE_PATHS" ]; then
    scan_runtime_nodes "$CUR_OUTBOUND_DIR"
    tags="$RUNTIME_NODE_TAGS_JSON"
  fi

  if [ -z "$tags" ] && ! is_reserved_outbound_tag "$CUR_CURRENT_TAG"; then
    tags="\"$(json_escape "$CUR_CURRENT_TAG")\""
  fi

  [ -n "$tags" ] || die "The current node directory does not have a checkout label available: $CUR_OUTBOUND_DIR"

  case "$selector_mode" in
    urltest | auto | dynamic_speed)
      cat > "$RUNTIME_OUTBOUNDS_FILE" << EOF
{
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
    },
    {
      "tag": "proxy",
      "type": "selector",
      "outbounds": [
        "Auto-Fastest",
        "direct",
        $tags
      ],
      "default": "Auto-Fastest",
      "interrupt_exist_connections": true
    },
    {
      "tag": "Auto-Fastest",
      "type": "urltest",
      "outbounds": [
        $tags
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "3m",
      "tolerance": 50
    }
  ]
}
EOF
      ;;
    manual | selector | manual_selection | Manual)
      cat > "$RUNTIME_OUTBOUNDS_FILE" << EOF
{
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
    },
    {
      "tag": "proxy",
      "type": "selector",
      "outbounds": [
        "direct",
        $tags
      ],
      "default": "$(json_escape "$CUR_CURRENT_TAG")",
      "interrupt_exist_connections": true
    }
  ]
}
EOF
      ;;
    *)
      die "Unknown Node Selection Mode: $selector_mode"
      ;;
  esac

  printf "%s\n" "$RUNTIME_OUTBOUNDS_FILE"
}
