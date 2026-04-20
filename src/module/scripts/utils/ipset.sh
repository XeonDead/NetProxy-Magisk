#!/system/bin/sh
# IPSET Kernel driver loading

readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
NETFILTER_DIR="/data/adb/netfilter"
. "$MODDIR/scripts/utils/common.sh"

load_drivers() {
  # Check if the driver directory exists
  if [ ! -d "$NETFILTER_DIR" ]; then
    log "INFO" "Integrated not detected IPSET drive，skip loading"
    return 0
  fi

  # Check if the kernel has been loaded ip_set
  if [ -d /sys/module/ip_set ]; then
    log "INFO" "The kernel is already built in or loaded IPSET module"
    return 0
  fi

  log "INFO" "Load integration IPSET Kernel driver..."
  cd "$NETFILTER_DIR" || return 1

  # Loader definition
  local loader="$MODDIR/bin/IPSET-LKM/ko-loader"
  [ -x "$loader" ] || chmod 0755 "$loader"

  i() { "$loader" "$@"; }

  # 1. Basic network module
  [ -f "iptables/ip6table_nat.ko" ] && i iptables/ip6table_nat.ko
  [ -f "ip_set.ko" ] && i ip_set.ko
  [ -f "ipset/ip_set.ko" ] && i ipset/ip_set.ko

  # 2. Algorithm module
  for m in bitmap_ip bitmap_ipmac bitmap_port; do
    [ -f "ipset/ip_set_$m.ko" ] && i "ipset/ip_set_$m.ko"
  done

  for m in ip ipmac ipmark ipport ipportip ipportnet mac net netiface netnet netport netportnet; do
    [ -f "ipset/ip_set_hash_$m.ko" ] && i "ipset/ip_set_hash_$m.ko"
  done

  [ -f "ipset/ip_set_list_set.ko" ] && i "ipset/ip_set_list_set.ko"

  # 3. Extended matching module
  [ -f "xt_set.ko" ] && i xt_set.ko
  [ -f "xt_addrtype.ko" ] && i xt_addrtype.ko

  log "INFO" "The driver loading process is completed"
}

case "$1" in
  load) load_drivers ;;
  *) echo "usage: $0 load" ;;
esac
