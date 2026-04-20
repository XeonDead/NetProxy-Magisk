#!/system/bin/sh
# sing-box Node source import script

set -e
set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly OUTBOUNDS_DIR="$MODDIR/config/singbox/outbounds"
readonly DEFAULT_DIR="$OUTBOUNDS_DIR/default"
readonly PROXYLINK_BIN="$MODDIR/bin/proxylink"
readonly LOG_FILE="$MODDIR/logs/subscription.log"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# show help
#######################################
show_help() {
  cat << EOF
usage: $(basename "$0") <Order> [parameter]

Import node:
  parse <node link> [Table of contents]       single link transfer sing-box node
  convert <document>                sing-box node to link
  file <document> [Table of contents]           file node or Clash YAML change sing-box node
  sub <Subscription link> [Table of contents]        Subscribe to transfer sing-box node，One file per node

Subscription management:
  add <name> <Subscription link>        Add subscription and import node
  update <name>                Update specified subscription
  update-all                   Update all subscriptions
  remove <name>                Delete subscription
  list                         List subscriptions

Example:
  $(basename "$0") parse "vless://..."
  $(basename "$0") file "/sdcard/clash.yaml"
  $(basename "$0") sub "https://example.com/sub" "$OUTBOUNDS_DIR/sub_demo"
EOF
}

#######################################
# examine proxylink environment
#######################################
check_proxylink() {
  [ -x "$PROXYLINK_BIN" ] || die "proxylink Does not exist or is not enforceable: $PROXYLINK_BIN"
}

#######################################
# Clean up filenames
#######################################
sanitize_name() {
  echo "$1" | sed 's/[\/\\:*?"<>| ]/_/g'
}

#######################################
# escape JSON string
#######################################
escape_json() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

#######################################
# Prepare output directory
#######################################
prepare_output_dir() {
  local target_dir="${1:-$DEFAULT_DIR}"

  mkdir -p "$target_dir" || die "Unable to create output directory: $target_dir"
  echo "$target_dir"
}

#######################################
# single link transfer sing-box
#######################################
import_parse() {
  local link="$1"
  local target_dir
  local old_pwd

  [ -n "$link" ] || die "usage: $(basename "$0") parse <node link> [Table of contents]"
  check_proxylink
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "Import a single node into: $target_dir"
  old_pwd="$(pwd)"
  cd "$target_dir" || die "Cannot enter output directory: $target_dir"
  "$PROXYLINK_BIN" -parse "$link" -insecure -format singbox -auto >> "$LOG_FILE" 2>&1
  cd "$old_pwd" || true
  log "INFO" "Single node import completed"
}

#######################################
# sing-box node to link
#######################################
export_link() {
  local file="$1"

  [ -n "$file" ] || die "usage: $(basename "$0") convert <document>"
  [ -f "$file" ] || die "File does not exist: $file"
  check_proxylink

  "$PROXYLINK_BIN" -singbox "$file" -format uri
}

#######################################
# File node transfer sing-box
#######################################
import_file() {
  local file="$1"
  local target_dir

  [ -n "$file" ] || die "usage: $(basename "$0") file <document> [Table of contents]"
  [ -f "$file" ] || die "File does not exist: $file"
  check_proxylink
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "Import file node to: $target_dir"
  "$PROXYLINK_BIN" -file "$file" -insecure -format singbox -dir "$target_dir" >> "$LOG_FILE" 2>&1
  log "INFO" "File node import completed"
}

#######################################
# Subscribe to transfer sing-box
#######################################
import_sub() {
  local url="$1"
  local target_dir

  [ -n "$url" ] || die "usage: $(basename "$0") sub <Subscription link> [Table of contents]"
  check_proxylink
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "Import the subscription node to: $target_dir"
  "$PROXYLINK_BIN" -sub "$url" -insecure -format singbox -dir "$target_dir" >> "$LOG_FILE" 2>&1
  log "INFO" "Subscription node import completed"
}

#######################################
# Write subscription meta information
#######################################
write_subscription_meta() {
  local name="$1"
  local url="$2"
  local target_dir="$3"

  cat > "$target_dir/_meta.json" << EOF
{
  "name": "$(escape_json "$name")",
  "url": "$(escape_json "$url")",
  "updated": "$(date -Iseconds)"
}
EOF
}

#######################################
# Add subscription
#######################################
add_subscription() {
  local name="$1"
  local url="$2"
  local safe_name sub_dir

  [ -n "$name" ] || die "usage: $(basename "$0") add <name> <Subscription link>"
  [ -n "$url" ] || die "usage: $(basename "$0") add <name> <Subscription link>"

  safe_name="$(sanitize_name "$name")"
  sub_dir="$OUTBOUNDS_DIR/sub_$safe_name"

  [ ! -d "$sub_dir" ] || die "Subscription already exists: $name"
  mkdir -p "$sub_dir" || die "Unable to create subscription directory: $sub_dir"

  write_subscription_meta "$name" "$url" "$sub_dir"
  import_sub "$url" "$sub_dir"
  log "INFO" "Subscription added completed: $name"
}

#######################################
# Update subscription
#######################################
update_subscription() {
  local name="$1"
  local safe_name sub_dir meta_file url

  [ -n "$name" ] || die "usage: $(basename "$0") update <name>"

  safe_name="$(sanitize_name "$name")"
  sub_dir="$OUTBOUNDS_DIR/sub_$safe_name"
  meta_file="$sub_dir/_meta.json"

  [ -f "$meta_file" ] || die "Subscription does not exist: $name"
  url="$(grep -o '"url"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_file" | sed 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  [ -n "$url" ] || die "Unable to read subscription link: $meta_file"

  find "$sub_dir" -name "*.json" ! -name "_meta.json" -delete
  import_sub "$url" "$sub_dir"
  write_subscription_meta "$name" "$url" "$sub_dir"
  log "INFO" "Subscription update completed: $name"
}

#######################################
# Update all subscriptions
#######################################
update_all_subscriptions() {
  local count=0 sub_dir meta_file name

  for sub_dir in "$OUTBOUNDS_DIR"/sub_*; do
    [ -d "$sub_dir" ] || continue
    meta_file="$sub_dir/_meta.json"
    [ -f "$meta_file" ] || continue

    name="$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_file" | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    [ -n "$name" ] || continue

    update_subscription "$name"
    count=$((count + 1))
  done

  log "INFO" "All subscription updates completed，common $count indivual"
}

#######################################
# Delete subscription
#######################################
remove_subscription() {
  local name="$1"
  local safe_name sub_dir

  [ -n "$name" ] || die "usage: $(basename "$0") remove <name>"

  safe_name="$(sanitize_name "$name")"
  sub_dir="$OUTBOUNDS_DIR/sub_$safe_name"

  [ -d "$sub_dir" ] || die "Subscription does not exist: $name"
  rm -rf "$sub_dir"
  log "INFO" "Subscription deleted: $name"
}

#######################################
# List subscriptions
#######################################
list_subscriptions() {
  local sub_dir meta_file name updated node_count count=0

  echo "Subscription list:"
  for sub_dir in "$OUTBOUNDS_DIR"/sub_*; do
    [ -d "$sub_dir" ] || continue
    meta_file="$sub_dir/_meta.json"
    [ -f "$meta_file" ] || continue

    name="$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_file" | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    updated="$(grep -o '"updated"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_file" | sed 's/.*"updated"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    node_count="$(find "$sub_dir" -name "*.json" ! -name "_meta.json" | wc -l | tr -d ' ')"

    echo "  - ${name:-$(basename "$sub_dir")} ($node_count nodes, updated on ${updated:-unknown})"
    count=$((count + 1))
  done

  [ "$count" -gt 0 ] || echo "  No subscription yet"
}

#######################################
# main entrance
#######################################
main() {
  local command="${1:-}"
  shift 2> /dev/null || true

  case "$command" in
    parse)
      import_parse "${1:-}" "${2:-}"
      ;;
    convert)
      export_link "${1:-}"
      ;;
    file | import)
      import_file "${1:-}" "${2:-}"
      ;;
    sub)
      import_sub "${1:-}" "${2:-}"
      ;;
    add)
      add_subscription "${1:-}" "${2:-}"
      ;;
    update)
      update_subscription "${1:-}"
      ;;
    update-all)
      update_all_subscriptions
      ;;
    remove | rm)
      remove_subscription "${1:-}"
      ;;
    list)
      list_subscriptions
      ;;
    -h | --help | help | "")
      show_help
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
}

main "$@"
