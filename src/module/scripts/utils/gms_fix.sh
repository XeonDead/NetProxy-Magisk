#!/system/bin/sh
#######################################
# 文件: gms_fix.sh
# 功能: 设备兼容性修复脚本，清理部分厂商 (红魔/ZTE、一加/ColorOS)
#       防火墙链中的 REJECT/DROP 拦截规则，避免误拦代理流量。
# 用法: gms_fix.sh [run]
# 依赖: common.sh、iptables/ip6tables。
#######################################

set -u  # 引用未定义变量报错

# 模块根目录与日志文件
readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly LOG_TAG="gms"  # 日志组件标签

. "$MODDIR/scripts/utils/common.sh"

#######################################
# 删除指定链中的拦截规则 (REJECT/DROP)
# 参数:
#   $1  命令 (iptables / ip6tables)
#   $2  目标链名
# 返回: 0 (无规则时直接返回)
#######################################
remove_block_rules_from_chain() {
  local cmd="$1"
  local chain="$2"
  local line_numbers line_num count=0

  # 取出链中所有 REJECT/DROP 规则的行号，按降序排列
  # (降序删除可避免删除后行号变动影响后续操作)
  line_numbers="$(
    $cmd -t filter -nvL "$chain" --line-numbers 2> /dev/null \
      | awk '/REJECT|DROP/ {print $1}' \
      | sort -rn
  )"

  # 无拦截规则则直接返回
  if [ -z "$line_numbers" ]; then
    log "INFO" "$cmd: $chain 链中未发现 REJECT 或 DROP 规则"
    return 0
  fi

  # 逐条按行号删除并计数
  for line_num in $line_numbers; do
    if $cmd -t filter -D "$chain" "$line_num" 2> /dev/null; then
      count=$((count + 1))
      log "INFO" "已删除 $cmd $chain 链中的第 $line_num 条拦截规则"
    else
      log "WARN" "删除失败: $cmd $chain 第 $line_num 条规则"
    fi
  done

  log "INFO" "$cmd: $chain 链共删除 $count 条拦截规则"
}

#######################################
# 按设备类型执行兼容性修复
# 通过特征链识别厂商，清理对应防火墙链中的拦截规则。
# 参数: 无
# 返回: 成功返回 0；iptables/ip6tables 均不存在返回 1
#######################################
fix_by_device() {
  local has_iptables=0
  local has_ip6tables=0
  local is_oneplus=0
  local is_redmagic=0
  local chain

  # 检测可用的 iptables 命令
  command_exists iptables && has_iptables=1
  command_exists ip6tables && has_ip6tables=1

  if [ "$has_iptables" -eq 0 ] && [ "$has_ip6tables" -eq 0 ]; then
    log "ERROR" "iptables 和 ip6tables 均不存在"
    return 1
  fi

  # 通过特征链判断设备厂商
  if iptables -t filter -L zte_fw_gms > /dev/null 2>&1; then
    is_redmagic=1
  elif iptables -t filter -L fw_INPUT > /dev/null 2>&1; then
    is_oneplus=1
  fi

  # 红魔 / ZTE：清理 zte_fw_gms 链
  if [ "$is_redmagic" -eq 1 ]; then
    log "INFO" "检测到红魔 / ZTE 规则，开始清理 zte_fw_gms"
    [ "$has_iptables" -eq 1 ] && remove_block_rules_from_chain "iptables" "zte_fw_gms"
    [ "$has_ip6tables" -eq 1 ] && remove_block_rules_from_chain "ip6tables" "zte_fw_gms"
  fi

  # 一加 / ColorOS：清理 fw_INPUT 与 fw_OUTPUT 链
  if [ "$is_oneplus" -eq 1 ]; then
    log "INFO" "检测到 OnePlus / ColorOS 规则，开始清理 fw_INPUT 与 fw_OUTPUT"
    for chain in fw_INPUT fw_OUTPUT; do
      [ "$has_iptables" -eq 1 ] && remove_block_rules_from_chain "iptables" "$chain"
      [ "$has_ip6tables" -eq 1 ] && remove_block_rules_from_chain "ip6tables" "$chain"
    done
  fi

  # 未匹配到已知厂商规则
  if [ "$is_redmagic" -eq 0 ] && [ "$is_oneplus" -eq 0 ]; then
    log "INFO" "未检测到需要修复的设备规则"
  fi
}

#######################################
# 显示用法说明
# 参数: 无
# 返回: 无
#######################################
show_usage() {
  cat << EOF
用法: $(basename "$0") [run]

命令:
  run      执行设备兼容性修复
EOF
}

#######################################
# 主入口：解析命令并分发
# 参数:
#   $1  命令 (run，默认 run)
# 返回: 依命令而定
#######################################
main() {
  case "${1:-run}" in
    run)
      log "INFO" "执行设备兼容性修复"
      fix_by_device
      log "INFO" "设备兼容性修复完成"
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
