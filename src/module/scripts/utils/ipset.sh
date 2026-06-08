#!/system/bin/sh
#######################################
# 文件: ipset.sh
# 功能: IPSET 内核驱动加载脚本，开机时加载模块自带的 ipset/netfilter
#       内核模块 (.ko)，供透明代理的 ipset 规则使用。
# 用法: ipset.sh load
# 依赖: common.sh；驱动文件位于 /data/adb/netfilter，加载器为 bin/IPSET-LKM/ko-loader。
#######################################

set -u  # 引用未定义变量报错

# 模块根目录与关键路径
readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"          # 服务日志
readonly NETFILTER_DIR="/data/adb/netfilter"          # 驱动 .ko 存放目录
readonly KO_LOADER="$MODDIR/bin/IPSET-LKM/ko-loader"  # 内核模块加载器

. "$MODDIR/scripts/utils/common.sh"

#######################################
# 加载集成的 IPSET 内核驱动
# 按依赖顺序依次加载 netfilter / ip_set / 各类 hash 模块。
# 参数: 无
# 返回: 0 (无驱动目录或内核已内置时直接跳过)
#######################################
load_drivers() {
  local module

  # 未集成驱动目录则跳过
  if [ ! -d "$NETFILTER_DIR" ]; then
    log "INFO" "未检测到集成的 IPSET 驱动目录，跳过加载"
    return 0
  fi

  # 内核已内置或已加载 ip_set 则无需重复加载
  if [ -d /sys/module/ip_set ]; then
    log "INFO" "内核已内置或已加载 IPSET 模块"
    return 0
  fi

  # 确保加载器可执行
  [ -x "$KO_LOADER" ] || chmod 0755 "$KO_LOADER"

  log "INFO" "开始加载集成 IPSET 内核驱动..."
  cd "$NETFILTER_DIR" || die "无法进入驱动目录: $NETFILTER_DIR"

  # 调用加载器加载单个 .ko 文件
  load_module() {
    "$KO_LOADER" "$@"
  }

  # 先加载基础依赖模块
  [ -f "iptables/ip6table_nat.ko" ] && load_module "iptables/ip6table_nat.ko"
  [ -f "ip_set.ko" ] && load_module "ip_set.ko"
  [ -f "ipset/ip_set.ko" ] && load_module "ipset/ip_set.ko"

  # 加载 bitmap 类型集合模块
  for module in bitmap_ip bitmap_ipmac bitmap_port; do
    [ -f "ipset/ip_set_$module.ko" ] && load_module "ipset/ip_set_$module.ko"
  done

  # 加载 hash 类型集合模块
  for module in ip ipmac ipmark ipport ipportip ipportnet mac net netiface netnet netport netportnet; do
    [ -f "ipset/ip_set_hash_$module.ko" ] && load_module "ipset/ip_set_hash_$module.ko"
  done

  # 加载 list 集合与 iptables 匹配模块
  [ -f "ipset/ip_set_list_set.ko" ] && load_module "ipset/ip_set_list_set.ko"
  [ -f "xt_set.ko" ] && load_module "xt_set.ko"
  [ -f "xt_addrtype.ko" ] && load_module "xt_addrtype.ko"

  log "INFO" "IPSET 驱动加载流程执行完成"
}

#######################################
# 显示用法说明
# 参数: 无
# 返回: 无
#######################################
show_usage() {
  cat << EOF
用法: $(basename "$0") load

命令:
  load      加载集成的 IPSET 驱动
EOF
}

#######################################
# 主入口：解析命令并分发
# 参数:
#   $1  命令 (load)
# 返回: 依命令而定
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
