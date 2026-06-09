#!/system/bin/sh
#######################################
# 文件: subscription.sh
# 功能: sing-box 节点与订阅管理脚本，封装 proxylink 完成节点链接/
#       文件/订阅的导入导出，以及订阅的增删改查与更新。
# 用法: subscription.sh <命令> [参数] [选项]，详见 show_help。
# 依赖: common.sh、nodes.sh、bin/proxylink。
#######################################

set -e  # 命令失败立即退出
set -u  # 引用未定义变量报错

# 模块根目录与关键路径
readonly MODDIR="$(cd "$(dirname "$0")/../.." && pwd)"
readonly OUTBOUNDS_DIR="$MODDIR/config/singbox/outbounds"  # 出站节点根目录
readonly DEFAULT_DIR="$OUTBOUNDS_DIR/default"              # 默认节点目录
readonly PROXYLINK_BIN="$MODDIR/bin/proxylink"            # proxylink 二进制
readonly LOG_FILE="$MODDIR/logs/subscription.log"         # 订阅日志文件
readonly LOG_TAG="sub"                                    # 日志组件标签

. "$MODDIR/scripts/utils/common.sh"
. "$MODDIR/scripts/utils/nodes.sh"

# 订阅请求参数 (由命令行 -ua / -hwid 选项设置)
SUB_UA=""    # 订阅请求 User-Agent
SUB_HWID=""  # 订阅请求 HWID 设备标识

# 本进程创建的临时目录列表，供退出时统一清理
SUB_TMP_DIRS=""

#######################################
# 清理本进程创建的所有临时目录
# 参数: 无
# 返回: 无 (由 trap 在退出/中断时自动调用)
#######################################
cleanup_sub_tmp() {
  local d
  for d in $SUB_TMP_DIRS; do
    [ -n "$d" ] && rm -rf "$d" 2> /dev/null
  done
}
# 注册退出与中断信号的兜底清理
trap cleanup_sub_tmp EXIT INT TERM

#######################################
# 显示帮助信息
# 参数: 无
# 返回: 无 (打印用法说明)
#######################################
show_help() {
  cat << EOF
用法: $(basename "$0") <命令> [参数] [选项]

节点导入:
  parse <节点链接> [目录]        单个链接转 sing-box 节点
  file <文件> [目录]            文件节点或 Clash YAML 转 sing-box 节点
  stdin [目录]                  从标准输入读取节点并转 sing-box 节点
  sub <订阅链接> [目录]         订阅转 sing-box 节点，每个节点一个文件
  convert <节点文件>            sing-box 节点转链接

订阅管理:
  add <名称> <订阅链接>         添加订阅并导入节点
  update <名称>                 更新指定订阅
  update-all                    更新全部订阅
  remove <名称>                 删除订阅
  list                          列出订阅

订阅选项 (适用于 sub / add / update / update-all):
  -ua <value>                   指定订阅请求 User-Agent；留空时自动处理
  -hwid <value>                 指定订阅请求 HWID 设备标识 (X-HWID 请求头)

示例:
  $(basename "$0") parse "vless://..."
  $(basename "$0") file "/sdcard/clash.yaml"
  $(basename "$0") sub "https://example.com/sub" "$OUTBOUNDS_DIR/sub_demo"
  $(basename "$0") sub "https://example.com/sub" -ua "ClashMeta" -hwid "abc123"
  $(basename "$0") convert "$OUTBOUNDS_DIR/default/example.json"
EOF
}

#######################################
# 检查 proxylink 二进制可用性
# 参数: 无
# 返回: 可用返回 0，否则退出
#######################################
check_proxylink() {
  require_file "$PROXYLINK_BIN" "proxylink 不存在: $PROXYLINK_BIN"
  [ -x "$PROXYLINK_BIN" ] || die "proxylink 不可执行: $PROXYLINK_BIN"
}

#######################################
# 准备输出目录 (不存在则创建)
# 参数:
#   $1  目标目录 (默认 DEFAULT_DIR)
# 返回: 标准输出打印目录路径
#######################################
prepare_output_dir() {
  local target_dir="${1:-$DEFAULT_DIR}"

  ensure_dir "$target_dir" "无法创建输出目录: $target_dir"
  printf "%s\n" "$target_dir"
}

#######################################
# 统一调用 proxylink 执行各类转换
# 参数:
#   $1  操作类型 (parse/file/stdin/sub/convert)
#   $2  操作对象 (链接/文件/订阅链接/节点文件)
#   $3  输出目录 (部分操作需要)
# 全局: 读取 SUB_UA/SUB_HWID 拼接订阅请求参数
# 返回: proxylink 退出码；未知操作则退出
#######################################
run_proxylink() {
  local action="$1"
  local value="$2"
  local target_dir="${3:-}"

  check_proxylink

  # 按操作类型组装并执行 proxylink 命令
  case "$action" in
    parse)
      # 单链接解析：在目标目录内执行，自动命名
      (
        cd "$target_dir" || exit 1
        "$PROXYLINK_BIN" -parse "$value" -insecure -format singbox -auto
      ) >> "$LOG_FILE" 2>&1
      ;;
    file)
      # 文件 (节点列表 / Clash YAML) 转换
      "$PROXYLINK_BIN" -file "$value" -insecure -format singbox -dir "$target_dir" >> "$LOG_FILE" 2>&1
      ;;
    stdin)
      # 从标准输入读取节点
      "$PROXYLINK_BIN" -insecure -format singbox -dir "$target_dir" >> "$LOG_FILE" 2>&1
      ;;
    sub)
      # 订阅转换：按需附加 UA / HWID 请求头参数
      set -- -sub "$value" -insecure -format singbox -dir "$target_dir"
      [ -n "$SUB_UA" ] && set -- "$@" -ua "$SUB_UA"
      [ -n "$SUB_HWID" ] && set -- "$@" -hwid "$SUB_HWID"
      "$PROXYLINK_BIN" "$@" >> "$LOG_FILE" 2>&1
      ;;
    convert)
      # sing-box 节点反向转为分享链接
      "$PROXYLINK_BIN" -singbox "$value" -format uri
      ;;
    *)
      die "未知 proxylink 操作: $action"
      ;;
  esac
}

#######################################
# 导入单个节点链接
# 参数:
#   $1  节点链接
#   $2  输出目录 (可选)
# 返回: 成功返回 0，失败则退出
#######################################
import_parse() {
  local link="$1"
  local target_dir

  [ -n "$link" ] || die "用法: $(basename "$0") parse <节点链接> [目录]"
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "开始导入单个节点: $target_dir"
  run_proxylink parse "$link" "$target_dir" || die "单个节点导入失败"
  log "INFO" "单个节点导入完成"
}

#######################################
# 从文件导入节点 (节点列表 / Clash YAML)
# 参数:
#   $1  文件路径
#   $2  输出目录 (可选)
# 返回: 成功返回 0，失败则退出
#######################################
import_file() {
  local file="$1"
  local target_dir

  [ -n "$file" ] || die "用法: $(basename "$0") file <文件> [目录]"
  require_file "$file" "文件不存在: $file"
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "开始导入文件节点: $target_dir"
  run_proxylink file "$file" "$target_dir" || die "文件节点导入失败"
  log "INFO" "文件节点导入完成"
}

#######################################
# 从标准输入导入节点
# 参数:
#   $1  输出目录 (可选)
# 返回: 成功返回 0，失败则退出
#######################################
import_stdin() {
  local target_dir
  target_dir="$(prepare_output_dir "${1:-}")"

  log "INFO" "开始导入标准输入节点: $target_dir"
  run_proxylink stdin "" "$target_dir" || die "标准输入节点导入失败"
  log "INFO" "标准输入节点导入完成"
}

#######################################
# 从订阅链接导入节点
# 参数:
#   $1  订阅链接
#   $2  输出目录 (可选)
# 返回: 成功返回 0，失败则退出
#######################################
import_sub() {
  local url="$1"
  local target_dir

  [ -n "$url" ] || die "用法: $(basename "$0") sub <订阅链接> [目录]"
  target_dir="$(prepare_output_dir "${2:-}")"

  log "INFO" "开始导入订阅节点: $target_dir"
  run_proxylink sub "$url" "$target_dir" || die "订阅节点导入失败"
  log "INFO" "订阅节点导入完成"
}

#######################################
# 将 sing-box 节点转为分享链接
# 参数:
#   $1  节点文件路径
# 返回: 标准输出打印链接；文件不存在则退出
#######################################
export_link() {
  local file="$1"

  [ -n "$file" ] || die "用法: $(basename "$0") convert <节点文件>"
  require_file "$file" "节点文件不存在: $file"
  check_proxylink
  run_proxylink convert "$file"
}

#######################################
# 清空订阅目录内的节点文件 (保留元数据)
# 参数:
#   $1  订阅目录
# 返回: 无
#######################################
clear_subscription_nodes() {
  local sub_dir="$1"
  local file

  # 仅删除节点文件，跳过 _meta.json
  for file in "$sub_dir"/*.json; do
    is_node_config_file "$file" || continue
    rm -f "$file"
  done
}

#######################################
# 拉取订阅节点并替换旧节点
# 先下载到临时目录，成功后再替换，失败则保留旧节点。
# 参数:
#   $1  订阅名
#   $2  订阅链接
#   $3  订阅目录
#   $4  请求 UA (默认 SUB_UA)
#   $5  请求 HWID (默认 SUB_HWID)
# 返回: 成功返回 0，拉取失败返回 1
#######################################
refresh_subscription_dir() {
  local name="$1"
  local url="$2"
  local sub_dir="$3"
  local ua="${4:-$SUB_UA}"
  local hwid_val="${5:-$SUB_HWID}"
  # 临时目录带 PID 后缀，避免并发更新同一订阅时命名冲突
  local tmp_dir="$sub_dir/_tmp.$$"

  # 登记到兜底清理列表
  SUB_TMP_DIRS="$SUB_TMP_DIRS $tmp_dir"

  # 先拉取到临时目录，失败则保留旧节点
  # UA/HWID 仅在子 shell 内生效，避免污染全局 (update-all 跨订阅复用)
  ensure_dir "$tmp_dir" "无法创建临时目录: $tmp_dir"
  if ! ( SUB_UA="$ua"; SUB_HWID="$hwid_val"; import_sub "$url" "$tmp_dir" ); then
    log "ERROR" "订阅拉取失败，保留旧节点: $name"
    rm -rf "$tmp_dir"
    return 1
  fi

  # 拉取成功：清空旧节点并移入新节点
  clear_subscription_nodes "$sub_dir"
  mv "$tmp_dir"/*.json "$sub_dir/" 2> /dev/null || true
  rm -rf "$tmp_dir"

  # 更新订阅元数据
  write_subscription_meta "$sub_dir" "$name" "$url" "$ua" "$hwid_val"
}

#######################################
# 从订阅目录的元数据读取信息并刷新该订阅
# 读取 name/url 及历史 ua/hwid，命令行 SUB_UA/SUB_HWID 优先。
# 参数:
#   $1  订阅目录
# 返回: 刷新成功返回 0；元数据缺失或拉取失败返回 1
#######################################
refresh_subscription_from_meta() {
  local sub_dir="$1"
  local meta_file="$sub_dir/_meta.json"
  local name url saved_ua saved_hwid use_ua use_hwid

  # 元数据缺失则跳过该订阅
  [ -f "$meta_file" ] || return 1

  name="$(read_subscription_meta_value "$meta_file" "name" || true)"
  url="$(read_subscription_meta_value "$meta_file" "url" || true)"
  [ -n "$url" ] || return 1
  [ -n "$name" ] || name="${sub_dir##*/}"

  # 命令行参数优先，缺省时回退到各订阅持久化值
  saved_ua="$(read_subscription_meta_value "$meta_file" "ua" || true)"
  saved_hwid="$(read_subscription_meta_value "$meta_file" "hwid" || true)"
  use_ua="${SUB_UA:-$saved_ua}"
  use_hwid="${SUB_HWID:-$saved_hwid}"

  refresh_subscription_dir "$name" "$url" "$sub_dir" "$use_ua" "$use_hwid"
}

#######################################
# 添加订阅并首次导入节点
# 参数:
#   $1  订阅名
#   $2  订阅链接
# 返回: 成功返回 0，已存在或失败则退出
#######################################
add_subscription() {
  local name="$1"
  local url="$2"
  local sub_dir

  [ -n "$name" ] || die "用法: $(basename "$0") add <名称> <订阅链接> [-ua <UA>] [-hwid <HWID>]"
  [ -n "$url" ] || die "用法: $(basename "$0") add <名称> <订阅链接> [-ua <UA>] [-hwid <HWID>]"

  sub_dir="$(subscription_dir_from_name "$OUTBOUNDS_DIR" "$name")"
  [ ! -d "$sub_dir" ] || die "订阅已存在: $name"

  # 首次拉取失败则回滚 (删除新建的订阅目录)
  ensure_dir "$sub_dir" "无法创建订阅目录: $sub_dir"
  if ! ( refresh_subscription_dir "$name" "$url" "$sub_dir" "$SUB_UA" "$SUB_HWID" ); then
    log "ERROR" "订阅添加失败，清理目录: $sub_dir"
    rm -rf "$sub_dir"
    exit 1
  fi
  log "INFO" "订阅添加完成: $name"
}

#######################################
# 更新指定订阅
# 参数:
#   $1  订阅名
# 全局: SUB_UA/SUB_HWID 命令行值优先，否则用元数据中的持久化值
# 返回: 成功返回 0，订阅不存在则退出
#######################################
update_subscription() {
  local name="$1"
  local sub_dir

  [ -n "$name" ] || die "用法: $(basename "$0") update <名称> [-ua <UA>] [-hwid <HWID>]"

  sub_dir="$(subscription_dir_from_name "$OUTBOUNDS_DIR" "$name")"
  require_file "$sub_dir/_meta.json" "订阅不存在: $name"

  refresh_subscription_from_meta "$sub_dir" || die "订阅更新失败: $name"
  log "INFO" "订阅更新完成: $name"
}

#######################################
# 更新全部订阅
# 单个订阅失败时记 WARN 并跳过，继续更新其余订阅。
# 参数: 无
# 返回: 无 (汇总成功/失败数)
#######################################
update_all_subscriptions() {
  local sub_dir name ok=0 failed=0

  # 遍历所有订阅目录
  for sub_dir in "$OUTBOUNDS_DIR"/sub_*; do
    [ -d "$sub_dir" ] || continue
    [ -f "$sub_dir/_meta.json" ] || continue

    name="${sub_dir##*/}"
    # 容错：单订阅失败不中断整体
    if refresh_subscription_from_meta "$sub_dir"; then
      ok=$((ok + 1))
    else
      failed=$((failed + 1))
      log "WARN" "订阅更新失败，已跳过: $name"
    fi
  done

  log "INFO" "全部订阅更新完成，成功 $ok 个，失败 $failed 个"
}

#######################################
# 删除指定订阅
# 参数:
#   $1  订阅名
# 返回: 成功返回 0，订阅不存在则退出
#######################################
remove_subscription() {
  local name="$1"
  local sub_dir

  [ -n "$name" ] || die "用法: $(basename "$0") remove <名称>"

  sub_dir="$(subscription_dir_from_name "$OUTBOUNDS_DIR" "$name")"
  [ -d "$sub_dir" ] || die "订阅不存在: $name"

  rm -rf "$sub_dir"
  log "INFO" "订阅已删除: $name"
}

#######################################
# 列出所有订阅及其节点数与更新时间
# 参数: 无
# 返回: 无 (打印订阅列表)
#######################################
list_subscriptions() {
  local sub_dir meta_file name updated node_count file count=0

  printf "订阅列表:\n"

  # 遍历订阅目录，统计节点数并输出
  for sub_dir in "$OUTBOUNDS_DIR"/sub_*; do
    [ -d "$sub_dir" ] || continue
    meta_file="$sub_dir/_meta.json"
    [ -f "$meta_file" ] || continue

    name="$(read_subscription_meta_value "$meta_file" "name" || true)"
    updated="$(read_subscription_meta_value "$meta_file" "updated" || true)"
    [ -n "$name" ] || name="${sub_dir##*/}"

    # 统计该订阅下的有效节点数
    node_count=0
    for file in "$sub_dir"/*.json; do
      is_node_config_file "$file" || continue
      node_count=$((node_count + 1))
    done

    printf "  - %s (%s 个节点，更新于 %s)\n" "$name" "$node_count" "${updated:-未知}"
    count=$((count + 1))
  done

  [ "$count" -gt 0 ] || printf "  暂无订阅\n"
}

#######################################
# 主入口：解析全局选项并分发子命令
# 参数:
#   $1   子命令
#   $@   子命令参数与 -ua/-hwid 选项
# 返回: 依子命令而定
#######################################
main() {
  local command="${1:-}"
  shift 2> /dev/null || true

  # 先提取 -ua / -hwid 全局选项，其余位置参数按原序保留
  # (将非选项参数从队首取出再追加回队尾，循环 remaining 次即复位顺序)
  local remaining=$#
  while [ "$remaining" -gt 0 ]; do
    case "$1" in
      -ua)
        SUB_UA="${2:-}"
        shift 2 2> /dev/null || shift
        remaining=$((remaining - 2))
        ;;
      -hwid)
        SUB_HWID="${2:-}"
        shift 2 2> /dev/null || shift
        remaining=$((remaining - 2))
        ;;
      *)
        set -- "$@" "$1"
        shift
        remaining=$((remaining - 1))
        ;;
    esac
  done

  # 按子命令分发
  case "$command" in
    parse)
      import_parse "${1:-}" "${2:-}"
      ;;
    file | import)
      import_file "${1:-}" "${2:-}"
      ;;
    stdin)
      import_stdin "${1:-}"
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
