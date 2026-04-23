#!/system/bin/sh
# sing-box Node and subscription management scripts

set -e
set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly OUTBOUNDS_DIR="$MODDIR/config/singbox/outbounds"
readonly DEFAULT_DIR="$OUTBOUNDS_DIR/default"
readonly PROXYLINK_BIN="$MODDIR/bin/proxylink"
readonly LOG_FILE="$MODDIR/logs/subscription.log"

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/nodes.sh"

#######################################
# show help
#######################################
show_help() {
  cat << EOF
usage: $(basename "$0") <Order> [parameter]

Node import:
  parse <node link> [Table of contents]        single link transfer sing-box node
  file <document> [Table of contents]            file node or Clash YAML change sing-box node
  sub <Subscription link> [Table of contents]         Subscribe to transfer sing-box node，One file per node
  convert <node file>            sing-box node to link

Subscription management:
  add <name> <Subscription link>         Add subscription and import node
  update <name>                 Update specified subscription
  update-all                    Update all subscriptions
  remove <name>                 Delete subscription
  list                          List subscriptions

Example:
  $(basename "$0") parse "vless://..."
  $(basename "$0") file "/sdcard/clash.yaml"
  $(basename "$0") sub "https://example.com/sub" "$OUTBOUNDS_DIR/sub_demo"
  $(basename "$0") convert "$OUTBOUNDS_DIR/default/default.json"
EOF
}

#######################################
# examine proxylink environment
#######################################
check_proxylink() {
  require_file "$PROXYLINK_BIN" "proxylink does not exist: $PROXYLINK_BIN"
  [ -x "$PROXYLINK_BIN" ] || die "proxylink Not enforceable: $PROXYLINK_BIN"
}

#######################################
# Prepare output directory
#######################################
prepare_output_dir() {
  local target_dir="${1:-$DEFAULT_DIR}"

  ensure_dir "$target_dir" "Unable to create output directory: $target_dir"
  printf "%s\n" "$target_dir"
}

#######################################
# Uniform execution proxylink
#######################################
run_proxylink() {
  local action="$1"
  local value="$2"
  local target_dir="${3:-}"

  check_proxylink

  case "$action" in
    parse)
      (
        cd "$target_dir" || exit 1
        "$PROXYLINK_BIN" -parse "$value" -insecure -format singbox -auto
      ) >> "$LOG_FILE" 2>&1
      ;;
    file)
      "$PROXYLINK_BIN" -file "$value" -insecure -format singbox -dir "$target_dir" >> "$LOG_FILE" 2>&1
      ;;
    sub)
      "$PROXYLINK_BIN" -sub "$value" -insecure -format singbox -dir "$target_dir" >> "$LOG_FILE" 2>&1
      ;;
    convert)
      "$PROXYLINK_BIN" -singbox "$value" -format uri
      ;;
    *)
      die "unknown proxylink operate: $action"
      ;;
  esac
}

#######################################
# single link transfer sing-box
#######################################
import_parse() {
  local link="$1"
  local target_dir

  [ -n "$link" ] || die "usage: $(basename "$0") parse <node link> [Table of contents]"
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "Start importing a single node: $target_dir"
  run_proxylink parse "$link" "$target_dir" || die "Single node import failed"
  log "INFO" "Single node import completed"
}

#######################################
# File node transfer sing-box
#######################################
import_file() {
  local file="$1"
  local target_dir

  [ -n "$file" ] || die "usage: $(basename "$0") file <document> [Table of contents]"
  require_file "$file" "File does not exist: $file"
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "Start importing file nodes: $target_dir"
  run_proxylink file "$file" "$target_dir" || die "File node import failed"
  log "INFO" "File node import completed"
}

#######################################
# Subscribe to transfer sing-box
#######################################
import_sub() {
  local url="$1"
  local target_dir

  [ -n "$url" ] || die "usage: $(basename "$0") sub <Subscription link> [Table of contents]"
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "Start importing subscription nodes: $target_dir"
  run_proxylink sub "$url" "$target_dir" || die "Subscription node import failed"
  log "INFO" "Subscription node import completed"
}

#######################################
# sing-box node to link
#######################################
export_link() {
  local file="$1"

  [ -n "$file" ] || die "usage: $(basename "$0") convert <node file>"
  require_file "$file" "Node file does not exist: $file"
  check_proxylink
  run_proxylink convert "$file"
}

#######################################
# Clean up the nodes in the subscription directory
#######################################
clear_subscription_nodes() {
  local sub_dir="$1"
  local file

  for file in "$sub_dir"/*.json; do
    is_node_config_file "$file" || continue
    rm -f "$file"
  done
}

#######################################
# Refresh subscription directory
#######################################
refresh_subscription_dir() {
  local name="$1"
  local url="$2"
  local sub_dir="$3"

  clear_subscription_nodes "$sub_dir"
  import_sub "$url" "$sub_dir"
  write_subscription_meta "$sub_dir" "$name" "$url"
}

#######################################
# Add subscription
#######################################
add_subscription() {
  local name="$1"
  local url="$2"
  local sub_dir

  [ -n "$name" ] || die "usage: $(basename "$0") add <name> <Subscription link>"
  [ -n "$url" ] || die "usage: $(basename "$0") add <name> <Subscription link>"

  sub_dir="$(subscription_dir_from_name "$OUTBOUNDS_DIR" "$name")"
  [ ! -d "$sub_dir" ] || die "Subscription already exists: $name"

  ensure_dir "$sub_dir" "Unable to create subscription directory: $sub_dir"
  refresh_subscription_dir "$name" "$url" "$sub_dir"
  log "INFO" "Subscription added completed: $name"
}

#######################################
# Update subscription
#######################################
update_subscription() {
  local name="$1"
  local sub_dir meta_file url saved_name

  [ -n "$name" ] || die "usage: $(basename "$0") update <name>"

  sub_dir="$(subscription_dir_from_name "$OUTBOUNDS_DIR" "$name")"
  meta_file="$sub_dir/_meta.json"

  require_file "$meta_file" "Subscription does not exist: $name"
  saved_name="$(read_subscription_meta_value "$meta_file" "name" || true)"
  url="$(read_subscription_meta_value "$meta_file" "url" || true)"

  [ -n "$url" ] || die "Unable to read subscription link: $meta_file"
  [ -n "$saved_name" ] || saved_name="$name"

  refresh_subscription_dir "$saved_name" "$url" "$sub_dir"
  log "INFO" "Subscription update completed: $saved_name"
}

#######################################
# Update all subscriptions
#######################################
update_all_subscriptions() {
  local sub_dir meta_file name url count=0

  for sub_dir in "$OUTBOUNDS_DIR"/sub_*; do
    [ -d "$sub_dir" ] || continue
    meta_file="$sub_dir/_meta.json"
    [ -f "$meta_file" ] || continue

    name="$(read_subscription_meta_value "$meta_file" "name" || true)"
    url="$(read_subscription_meta_value "$meta_file" "url" || true)"
    [ -n "$url" ] || continue
    [ -n "$name" ] || name="$(basename "$sub_dir")"

    refresh_subscription_dir "$name" "$url" "$sub_dir"
    count=$((count + 1))
  done

  log "INFO" "All subscription updates completed，common $count indivual"
}

#######################################
# Delete subscription
#######################################
remove_subscription() {
  local name="$1"
  local sub_dir

  [ -n "$name" ] || die "usage: $(basename "$0") remove <name>"

  sub_dir="$(subscription_dir_from_name "$OUTBOUNDS_DIR" "$name")"
  [ -d "$sub_dir" ] || die "Subscription does not exist: $name"

  rm -rf "$sub_dir"
  log "INFO" "Subscription deleted: $name"
}

#######################################
# List subscriptions
#######################################
list_subscriptions() {
  local sub_dir meta_file name updated node_count file count=0

  printf "Subscription list:\n"

  for sub_dir in "$OUTBOUNDS_DIR"/sub_*; do
    [ -d "$sub_dir" ] || continue
    meta_file="$sub_dir/_meta.json"
    [ -f "$meta_file" ] || continue

    name="$(read_subscription_meta_value "$meta_file" "name" || true)"
    updated="$(read_subscription_meta_value "$meta_file" "updated" || true)"
    [ -n "$name" ] || name="$(basename "$sub_dir")"

    node_count=0
    for file in "$sub_dir"/*.json; do
      is_node_config_file "$file" || continue
      node_count=$((node_count + 1))
    done

    printf "  - %s (%s nodes，updated on %s)\n" "$name" "$node_count" "${updated:-unknown}"
    count=$((count + 1))
  done

  [ "$count" -gt 0 ] || printf "  No subscription yet\n"
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
    file | import)
      import_file "${1:-}" "${2:-}"
      ;;
    sub)
      import_sub "${1:-}" "${2:-}"
      ;;
    convert)
      export_link "${1:-}"
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
