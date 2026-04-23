#!/system/bin/sh
# Node and subscription helper functions

readonly NODE_RECORD_DELIM="$(printf '\t')"
NODE_SCAN_VALID_COUNT=0
NODE_SCAN_SKIPPED_COUNT=0

#######################################
# Determine whether it is a node configuration file
#######################################
is_node_config_file() {
  local file="$1"

  [ -f "$file" ] || return 1
  [ "${file##*/}" != "_meta.json" ] || return 1
}

#######################################
# Read outbound tag
#######################################
detect_outbound_tag() {
  local config_file="$1"

  [ -f "$config_file" ] || return 1
  grep -m 1 -E '"tag"[[:space:]]*:' "$config_file" 2> /dev/null | sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

#######################################
# Determine whether to retain labels for selectors
#######################################
is_reserved_outbound_tag() {
  case "$1" in
    direct | block | Proxy | Auto-Fastest | default) return 0 ;;
    *) return 1 ;;
  esac
}

#######################################
# Clean up subscription names
#######################################
sanitize_subscription_name() {
  printf "%s" "$1" | sed 's/[\/\\:*?"<>| ]/_/g'
}

#######################################
# Get subscription directory path
#######################################
subscription_dir_from_name() {
  local outbounds_dir="$1"
  local name="$2"

  printf "%s/sub_%s\n" "$outbounds_dir" "$(sanitize_subscription_name "$name")"
}

#######################################
# Read subscription metadata fields
#######################################
read_subscription_meta_value() {
  local meta_file="$1"
  local key="$2"

  [ -f "$meta_file" ] || return 1
  grep -o '"'$key'"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_file" 2> /dev/null | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

#######################################
# Write subscription metadata
#######################################
write_subscription_meta() {
  local target_dir="$1"
  local name="$2"
  local url="$3"

  cat > "$target_dir/_meta.json" << EOF
{
  "name": "$(json_escape "$name")",
  "url": "$(json_escape "$url")",
  "updated": "$(date -Iseconds)"
}
EOF
}

#######################################
# Get subscription display name
#######################################
subscription_display_name() {
  local sub_dir="$1"
  local meta_file="$sub_dir/_meta.json"
  local name

  name="$(read_subscription_meta_value "$meta_file" "name" 2> /dev/null || true)"
  if [ -n "$name" ]; then
    printf "%s\n" "$name"
  else
    printf "%s\n" "$(basename "$sub_dir")"
  fi
}

#######################################
# Reset node scan count
#######################################
reset_node_scan_counters() {
  NODE_SCAN_VALID_COUNT=0
  NODE_SCAN_SKIPPED_COUNT=0
}

#######################################
# Write a node scan record
#######################################
append_node_record() {
  local output_file="$1"
  local file="$2"
  local tag="$3"
  local source="$4"
  local is_current="$5"

  printf "%s\t%s\t%s\t%s\t%s\n" "$file" "$(basename "$file")" "$tag" "$source" "$is_current" >> "$output_file"
}

#######################################
# Scan nodes in a single directory
#######################################
scan_nodes_in_dir() {
  local dir="$1"
  local current_config="$2"
  local source="$3"
  local output_file="$4"
  local append_mode="${5:-0}"
  local file tag is_current

  if [ "$append_mode" != "1" ]; then
    : > "$output_file"
    reset_node_scan_counters
  fi

  for file in "$dir"/*.json; do
    is_node_config_file "$file" || continue
    tag="$(detect_outbound_tag "$file" || true)"

    if [ -z "$tag" ]; then
      NODE_SCAN_SKIPPED_COUNT=$((NODE_SCAN_SKIPPED_COUNT + 1))
      continue
    fi

    is_current=0
    [ "$file" = "$current_config" ] && is_current=1
    append_node_record "$output_file" "$file" "$tag" "$source" "$is_current"
    NODE_SCAN_VALID_COUNT=$((NODE_SCAN_VALID_COUNT + 1))
  done
}

#######################################
# Scan all nodes
#######################################
scan_all_nodes() {
  local outbounds_dir="$1"
  local current_config="$2"
  local output_file="$3"
  local sub_dir source

  : > "$output_file"
  reset_node_scan_counters

  scan_nodes_in_dir "$outbounds_dir/default" "$current_config" "default node" "$output_file" 1

  for sub_dir in "$outbounds_dir"/sub_*; do
    [ -d "$sub_dir" ] || continue
    source="subscription: $(subscription_display_name "$sub_dir")"
    scan_nodes_in_dir "$sub_dir" "$current_config" "$source" "$output_file" 1
  done
}

#######################################
# Read the current node record
#######################################
find_current_node_from_scan() {
  local scan_file="$1"
  local path name tag source is_current

  while IFS="$NODE_RECORD_DELIM" read -r path name tag source is_current; do
    [ "$is_current" = "1" ] || continue
    printf "%s\n" "$path"
    return 0
  done < "$scan_file"

  return 1
}

#######################################
# parse node
#######################################
resolve_node_from_scan() {
  local scan_file="$1"
  local query="$2"
  local match_count=0
  local first_match=""
  local path name tag source is_current base

  [ -n "$query" ] || die "Please specify node name、label or path"

  if [ -f "$query" ]; then
    printf "%s\n" "$query"
    return 0
  fi

  while IFS="$NODE_RECORD_DELIM" read -r path name tag source is_current; do
    base="${name%.json}"

    if [ "$query" = "$path" ] || [ "$query" = "$name" ] || [ "$query" = "$base" ] || [ "$query" = "$tag" ]; then
      match_count=$((match_count + 1))
      [ "$match_count" -eq 1 ] && first_match="$path"
    fi
  done < "$scan_file"

  case "$match_count" in
    0)
      die "Node not found: $query"
      ;;
    1)
      printf "%s\n" "$first_match"
      ;;
    *)
      die "Find multiple nodes with the same name，Please use a more precise filename or full path"
      ;;
  esac
}
