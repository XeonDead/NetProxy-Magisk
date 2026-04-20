#!/system/bin/sh
# sing-box Runtime configuration helper functions

#######################################
# Get the directory where the current node is located
#######################################
get_current_outbounds_dir() {
  local current_config="$1"
  local current_dir

  current_dir="${current_config%/*}"
  [ "$current_dir" != "$current_config" ] || die "Unable to resolve current node directory: $current_config"
  [ -d "$current_dir" ] || die "The current node directory does not exist: $current_dir"

  echo "$current_dir"
}

#######################################
# Determine whether it is a node configuration file
#######################################
is_node_config_file() {
  local file="$1"

  [ -f "$file" ] || return 1
  [ "${file##*/}" != "_meta.json" ] || return 1
}

#######################################
# escape JSON string
#######################################
json_escape() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

#######################################
# Append outbound tags to JSON array fragment
#######################################
append_selector_tag() {
  local tags="$1"
  local tag="$2"
  local escaped

  escaped="$(json_escape "$tag")"
  if [ -n "$tags" ]; then
    printf "%s, \"%s\"" "$tags" "$escaped"
  else
    printf "\"%s\"" "$escaped"
  fi
}

# runtime context（Depend on initialize_runtime_context filling）
CUR_OUTBOUND_CONFIG=""
CUR_OUTBOUND_DIR=""
CUR_OUTBOUND_MODE=""
CUR_SELECTOR_MODE=""

# Node scan results（Depend on write_runtime_outbounds filling）
SCAN_NODE_ARGS=""
SCAN_NODE_COUNT=0
SCAN_SKIPPED_COUNT=0

#######################################
# Initialization startup environment and basic configuration
#######################################
initialize_runtime_context() {
  # Basic environment check
  [ -x "${SING_BOX_BIN:-}" ] || die "sing-box Binary does not exist or is not executable"
  [ -f "${MODULE_CONF:-}" ] || die "Module configuration file does not exist"
  [ -f "${TPROXY_CONF_DIR:-}/tproxy.conf" ] || die "Transparent proxy configuration file does not exist"

  # Loading modules and transparent proxy configuration
  . "$MODULE_CONF"
  . "$TPROXY_CONF_DIR/tproxy.conf"

  # Extract and verify the current node path
  CUR_OUTBOUND_CONFIG="$(strip_quotes "${CURRENT_CONFIG:-}")"
  [ -n "$CUR_OUTBOUND_CONFIG" ] || die "CURRENT_CONFIG undefined，Please select the node first"
  [ -f "$CUR_OUTBOUND_CONFIG" ] || die "The specified node configuration file does not exist: $CUR_OUTBOUND_CONFIG"

  # Determine running mode and selector mode
  CUR_OUTBOUND_MODE="${OUTBOUND_MODE:-rule}"
  CUR_SELECTOR_MODE="${SELECTOR_MODE:-urltest}"
  
  # Get the current node directory
  CUR_OUTBOUND_DIR="$(get_current_outbounds_dir "$CUR_OUTBOUND_CONFIG")" || return 1
}

#######################################
# Scan nodes and generate runtime outbound configuration
#######################################
write_runtime_outbounds() {
  local output="${RUNTIME_DIR:?RUNTIME_DIR undefined}/outbounds.json"
  local current_config="${1:-$CUR_OUTBOUND_CONFIG}"
  local current_dir="${CUR_OUTBOUND_DIR:-$(get_current_outbounds_dir "$current_config")}"
  local selector_mode="${2:-$CUR_SELECTOR_MODE}"
  local current_tag current_tag_json tags="" f tag

  SCAN_NODE_ARGS=""
  SCAN_NODE_COUNT=0
  SCAN_SKIPPED_COUNT=0

  current_tag="$(detect_outbound_tag "$current_config")"
  [ -n "$current_tag" ] || die "Unable to read tag from current outbound configuration: $current_config"
  current_tag_json="$(json_escape "$current_tag")"

  mkdir -p "$RUNTIME_DIR" || die "Unable to create runtime configuration directory: $RUNTIME_DIR"

  log "INFO" "Scanning node directory: $current_dir"

  # Scan the current node directory
  for f in "$current_dir"/*.json; do
    is_node_config_file "$f" || continue
    tag="$(detect_outbound_tag "$f")"
    
    if [ -z "$tag" ]; then
      SCAN_SKIPPED_COUNT=$((SCAN_SKIPPED_COUNT + 1))
      continue
    fi

    # Collect startup parameters（All nodes are loaded）
    SCAN_NODE_ARGS="$SCAN_NODE_ARGS -c \"$f\""
    SCAN_NODE_COUNT=$((SCAN_NODE_COUNT + 1))

    # Collection of switchable labels（filter out default To prevent preemption of the speed test group）
    if [ "$tag" != "default" ]; then
      tags="$(append_selector_tag "$tags" "$tag")"
    fi
  done

  # When no switchable node is found，At least keep the current node for speed testing/choose
  [ -n "$tags" ] || tags="$(append_selector_tag "" "$current_tag")"

  case "$selector_mode" in
    urltest | auto | Dynamic_speed_measurement)
      cat > "$output" << EOF
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
    manual | selector | Manual_selection | Manual)
      cat > "$output" << EOF
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
      "default": "$current_tag_json",
      "interrupt_exist_connections": true
    }
  ]
}
EOF
      ;;
    *)
      die "Unknown node selection mode: $selector_mode"
      ;;
  esac

  echo "$output"
}
