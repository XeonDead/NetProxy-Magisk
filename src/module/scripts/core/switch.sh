#!/system/bin/sh
#######################################
# 文件: switch.sh
# 功能: sing-box 出站切换脚本，负责切换当前节点配置或出站模式。
#       优先通过控制接口热切换，失败时回退为重启服务生效。
# 用法: switch.sh {config|mode} <参数>
#       config <配置文件>            切换当前节点配置
#       mode <rule|global|direct>   切换出站模式
# 依赖: common.sh、config.sh、api.sh、nodes.sh。
#######################################

set -u  # 引用未定义变量报错

# 模块根目录与关键路径
readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly MODULE_CONF="$MODDIR/config/module.conf"           # 模块配置
readonly SERVICE_SCRIPT="$MODDIR/scripts/core/service.sh"   # 服务管理脚本
readonly SING_BOX_BIN="$MODDIR/bin/sing-box"               # sing-box 二进制
readonly LOG_FILE="$MODDIR/logs/service.log"               # 服务日志
# 是否允许通过重启服务来应用配置 (启动阶段会置 0，防止递归重启)
readonly SWITCH_ALLOW_RESTART="${SWITCH_ALLOW_RESTART:-1}"

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/config.sh"
. "$MODDIR/scripts/utils/api.sh"
. "$MODDIR/scripts/utils/nodes.sh"

#######################################
# 判断 sing-box 是否在运行
# 参数: 无
# 返回: 0=运行中，非 0=未运行
#######################################
is_service_running() {
  [ -n "$(get_pid "$SING_BOX_BIN")" ]
}

#######################################
# 在允许的情况下重启服务以应用配置
# 参数: 无
# 全局: SWITCH_ALLOW_RESTART 为 1 时才执行重启
# 返回: 重启成功返回 0；不允许重启返回 1
#######################################
restart_service_if_allowed() {
  if [ "$SWITCH_ALLOW_RESTART" = "1" ]; then
    log "INFO" "正在重启 sing-box 核心服务以应用配置..."
    LOG_STDERR=0 sh "$SERVICE_SCRIPT" restart core || die "重启 sing-box 服务失败"
  else
    log "WARN" "当前阶段不允许通过重启应用配置"
    return 1
  fi
}

#######################################
# 切换当前节点配置
# 先持久化到模块配置，再尝试热切换，失败则重启服务。
# 参数:
#   $1  节点配置文件路径
# 返回: 成功返回 0；仅完成持久化时返回 1
#######################################
switch_config() {
  local config_file="$1"
  local target_tag

  require_file "$MODULE_CONF" "模块配置文件不存在: $MODULE_CONF"
  require_file "$config_file" "节点配置文件不存在: $config_file"

  log "INFO" "========== 开始切换 sing-box 节点配置 =========="
  log "INFO" "目标节点文件: $config_file"

  # 持久化当前节点路径并读取其出站标签
  set_conf "$MODULE_CONF" "CURRENT_CONFIG" "$(quote_conf "$config_file")"
  target_tag="$(detect_outbound_tag "$config_file" || true)"

  # 服务未运行时仅持久化，下次启动生效
  if ! is_service_running; then
    log "INFO" "sing-box 未运行，新的节点配置将在下次启动时生效"
    log "INFO" "========== 节点配置切换完成 =========="
    return 0
  fi

  # 有标签时优先通过控制接口热切换
  if [ -n "$target_tag" ]; then
    if api_select_proxy "$target_tag"; then
      log "INFO" "已通过控制接口切换到节点: $target_tag"
      log "INFO" "========== 节点配置切换完成 =========="
      return 0
    fi
    log "INFO" "当前运行实例未加载目标节点或控制接口切换失败，准备重启服务"
  else
    log "INFO" "无法读取目标节点标签，准备重启服务"
  fi

  # 热切换失败则回退为重启服务
  restart_service_if_allowed || {
    log "WARN" "本次仅完成配置持久化，等待下次服务重启生效"
    return 1
  }

  log "INFO" "========== 节点配置切换完成 =========="
}

#######################################
# 切换出站模式
# 先持久化模式，再尝试通过控制接口切换，失败则重启服务。
# 参数:
#   $1  目标模式 (rule/global/direct/AllowAds)
# 返回: 成功返回 0；仅完成持久化时返回 1
#######################################
switch_mode() {
  local target_mode="$1"

  # 校验模式合法性
  case "$target_mode" in
    rule | global | direct | AllowAds) ;;
    *)
      die "未知模式: $target_mode"
      ;;
  esac

  require_file "$MODULE_CONF" "模块配置文件不存在: $MODULE_CONF"

  log "INFO" "========== 开始切换 sing-box 出站模式: $target_mode =========="
  # 持久化目标模式
  set_conf "$MODULE_CONF" "OUTBOUND_MODE" "$target_mode"

  # 服务未运行时仅持久化，下次启动生效
  if ! is_service_running; then
    log "INFO" "sing-box 未运行，新的出站模式将在下次启动时生效"
    log "INFO" "========== 出站模式切换完成 =========="
    return 0
  fi

  # 优先通过控制接口切换
  if api_set_mode "$target_mode"; then
    log "INFO" "已通过控制接口切换出站模式"
    log "INFO" "========== 出站模式切换完成 =========="
    return 0
  fi

  # 接口切换失败则回退为重启服务
  log "WARN" "控制接口切换模式失败，准备重启服务"
  restart_service_if_allowed || {
    log "WARN" "本次仅完成模式持久化，等待下次服务重启生效"
    return 1
  }

  log "INFO" "========== 出站模式切换完成 =========="
}

#######################################
# 显示用法说明
# 参数: 无
# 返回: 无
#######################################
show_usage() {
  cat << EOF
用法: $(basename "$0") {config|mode} <参数>

命令:
  config <配置文件>              切换当前节点配置
  mode <rule|global|direct>     切换出站模式
EOF
}

#######################################
# 主入口：解析命令并分发
# 参数:
#   $1  命令 (config/mode)
#   $2  对应参数 (配置文件 / 模式名)
# 返回: 依命令而定
#######################################
main() {
  local command="${1:-}"
  local value="${2:-}"

  case "$command" in
    config)
      # 切换节点配置，缺少参数则打印用法并退出
      [ -n "$value" ] || { show_usage; exit 1; }
      switch_config "$value"
      ;;
    mode)
      # 切换出站模式，缺少参数则打印用法并退出
      [ -n "$value" ] || { show_usage; exit 1; }
      switch_mode "$value"
      ;;
    -h | --help | help | "")
      # 无命令时打印用法 (空命令视为错误退出)
      show_usage
      [ -n "$command" ] || exit 1
      ;;
    *)
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
