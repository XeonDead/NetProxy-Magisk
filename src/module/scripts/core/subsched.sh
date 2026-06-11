#!/system/bin/sh
#######################################
# 文件: subsched.sh
# 功能: 订阅定时更新调度守护。用 busybox crond 按配置的间隔小时数周期性
#       调用 subscription.sh update-all 更新全部订阅。
# 用法:
#   subsched.sh sync    按 module.conf 启停 crond 守护并写入 crontab
#   subsched.sh stop    停止本模块的 crond 守护
#   subsched.sh run     立即执行一次全部订阅更新 (供 cron 触发)
# 依赖: common.sh、config.sh、subscription.sh、busybox(crond applet)。
#######################################

set -u  # 引用未定义变量报错

# 模块根目录与关键路径
readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly MODULE_CONF="$MODDIR/config/module.conf"
readonly SUB_SCRIPT="$MODDIR/scripts/core/subscription.sh"
# crond 工作目录放 tmpfs (/dev)：不磨损 flash、重启自动清空
readonly CRON_DIR="/dev/netproxy/cron"
readonly CRONTAB_FILE="$CRON_DIR/root"   # busybox crond 按 DIR/<用户名> 读取，root 运行即 root
readonly LOG_FILE="$MODDIR/logs/service.log"
readonly LOG_TAG="subsched"

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"

readonly BUSYBOX="$(detect_busybox)"

# PLACEHOLDER_SUBSCHED

#######################################
# 停止本模块的 crond 守护 (按 -c CRON_DIR 标识匹配，避免误杀系统 crond)
# 返回: 无
#######################################
stop_cron() {
  local pid
  for pid in $(pidof crond 2> /dev/null); do
    if [ -f "/proc/$pid/cmdline" ] && grep -q "$CRON_DIR" "/proc/$pid/cmdline" 2> /dev/null; then
      kill "$pid" 2> /dev/null || true
    fi
  done
}

#######################################
# 立即执行一次全部订阅更新 (供 cron 触发)
# 返回: subscription.sh 的退出码
#######################################
run_update() {
  log "INFO" "定时任务触发：开始更新全部订阅"
  sh "$SUB_SCRIPT" update-all
}

#######################################
# 按 module.conf 启停 crond 守护
#   关闭 -> 停 crond；开启 -> 写 crontab 并(重)启 crond
# 返回: 无
#######################################
sync_cron() {
  local enabled interval minute self

  enabled="$(read_conf "$MODULE_CONF" "SUB_AUTO_UPDATE" "0")"
  interval="$(read_conf "$MODULE_CONF" "SUB_UPDATE_INTERVAL" "12")"

  # 先停旧守护，保证幂等
  stop_cron

  if [ "$enabled" != "1" ]; then
    return 0
  fi

  # 间隔校验：取正整数，超出 1..23 的按 cron 小时步进语义夹取/兜底
  case "$interval" in
    *[!0-9]* | "") interval=12 ;;
  esac
  [ "$interval" -ge 1 ] 2> /dev/null || interval=12
  [ "$interval" -le 23 ] 2> /dev/null || interval=23

  # 错峰分钟 (避免整点拥堵)，固定 7 分
  minute=7
  self="$(realpath "$0" 2> /dev/null || echo "$0")"

  mkdir -p "$CRON_DIR" 2> /dev/null || true
  # 标准 5 字段：分 时 日 月 周；每 interval 小时的第 minute 分执行
  printf '%s */%s * * * sh "%s" run\n' "$minute" "$interval" "$self" > "$CRONTAB_FILE"

  # 后台启动 crond (-c 指定 crontab 目录，-b 后台)
  "$BUSYBOX" crond -c "$CRON_DIR" -b -L /dev/null 2> /dev/null \
    && log "INFO" "订阅定时更新已启用：每 ${interval} 小时" \
    || log "WARN" "crond 启动失败，定时更新未生效"
}

#######################################
# 主入口
#######################################
main() {
  case "${1:-}" in
    sync) sync_cron ;;
    stop) stop_cron ;;
    run) run_update ;;
    *)
      printf "用法: %s {sync|stop|run}\n" "$(basename "$0")" >&2
      exit 1
      ;;
  esac
}

main "$@"

