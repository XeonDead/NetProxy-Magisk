#!/system/bin/sh
# IPSET Driver Load Script

set -u

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly NETFILTER_DIR="/data/adb/netfilter"
readonly KO_LOADER="$MODDIR/bin/IPSET-LKM/ko-loader"

. "$MODDIR/scripts/utils/common.sh"

#######################################
# Load kernel driver
#######################################
load_drivers() {
  local module

  if [ ! -d "$NETFILTER_DIR" ]; then
    log "INFO" "Not detected IPSET Driver Directory, Skip Load"
    return 0
  fi

  if [ -d /sys/module/ip_set ]; then
    log "INFO" "kernel is built or loaded IPSET Modules"
    return 0
  fi

  [ -x "$KO_LOADER" ] || chmod 0755 "$KO_LOADER"

  log "INFO" "Start loading integration IPSET kernel driver..."
  cd "$NETFILTER_DIR" || die "Could not enter driver directory: $NETFILTER_DIR"

  load_module() {
    "$KO_LOADER" "$@"
  }

  [ -f "iptables/ip6table_nat.ko" ] && load_module "iptables/ip6table_nat.ko"
  [ -f "ip_set.ko" ] && load_module "ip_set.ko"
  [ -f "ipset/ip_set.ko" ] && load_module "ipset/ip_set.ko"

  for module in bitmap_ip bitmap_ipmac bitmap_port; do
    [ -f "ipset/ip_set_$module.ko" ] && load_module "ipset/ip_set_$module.ko"
  done

  for module in ip ipmac ipmark ipport ipportip ipportnet mac net netiface netnet netport netportnet; do
    [ -f "ipset/ip_set_hash_$module.ko" ] && load_module "ipset/ip_set_hash_$module.ko"
  done

  [ -f "ipset/ip_set_list_set.ko" ] && load_module "ipset/ip_set_list_set.ko"
  [ -f "xt_set.ko" ] && load_module "xt_set.ko"
  [ -f "xt_addrtype.ko" ] && load_module "xt_addrtype.ko"

  log "INFO" "IPSET Driver loading process complete"
}

#######################################
# Show Help
#######################################
show_usage() {
  cat << EOF
Usage: $(basename "$0") load

Command:
  load      Load integrated IPSET Driver
EOF
}

#######################################
# Main entrance
#######################################
main() {
  case "${1:-}" in
    load)
      load_drivers
      ;;
    -h | --help | help)
      show_usage
      ;;
    *)
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
