#!/system/bin/sh
#######################################
# 文件: runtime.sh
# 功能: sing-box 运行时配置辅助函数，负责读取模块配置、扫描
#       当前节点目录、生成运行时出站 (selector / urltest) 配置。
# 用法: 由 service.sh 等通过 . "$MODDIR/scripts/core/runtime.sh" 引入。
#       依赖 common.sh (NL/TAB/die)、config.sh (read_conf)、nodes.sh。
#######################################

# 当前出站上下文 (由 initialize_runtime_context 填充)
CUR_OUTBOUND_CONFIG=""   # 当前节点配置文件路径
CUR_OUTBOUND_DIR=""      # 当前节点所在目录
CUR_OUTBOUND_MODE=""     # 出站模式 (rule/global/direct)
CUR_SELECTOR_MODE=""     # 节点选择模式 (urltest/manual)
CUR_CURRENT_TAG=""       # 当前节点的出站标签

# 节点扫描结果 (由 scan_runtime_nodes 填充)
RUNTIME_OUTBOUNDS_FILE=""   # 运行时出站配置输出路径
RUNTIME_NODE_PATHS=""       # 扫描到的节点文件路径列表 (换行分隔)
RUNTIME_NODE_TAGS_JSON=""   # 节点标签的 JSON 数组片段
RUNTIME_NODE_COUNT=0        # 有效节点数
RUNTIME_SKIPPED_COUNT=0     # 跳过 (无 tag) 的文件数

#######################################
# 初始化运行时上下文
# 从模块配置读取当前节点/模式，并校验相关文件与目录。
# 参数: 无
# 全局: 读取 MODULE_CONF/SINGBOX_DIR/CONFDIR/RUNTIME_DIR；填充 CUR_* 与 RUNTIME_OUTBOUNDS_FILE
# 返回: 成功返回 0，校验失败则退出
#######################################
initialize_runtime_context() {
  # 校验必需的配置文件与目录
  require_file "${MODULE_CONF:-}" "模块配置文件不存在: ${MODULE_CONF:-未定义}"
  require_dir "${SINGBOX_DIR:-}" "sing-box 配置目录不存在: ${SINGBOX_DIR:-未定义}"
  require_dir "${CONFDIR:-}" "通用配置目录不存在: ${CONFDIR:-未定义}"
  require_dir "${RUNTIME_DIR:-}" "运行时目录不存在: ${RUNTIME_DIR:-未定义}"

  # 读取当前节点路径与运行模式
  CUR_OUTBOUND_CONFIG="$(read_conf "$MODULE_CONF" "CURRENT_CONFIG" "")"
  CUR_OUTBOUND_MODE="$(read_conf "$MODULE_CONF" "OUTBOUND_MODE" "rule")"
  CUR_SELECTOR_MODE="$(read_conf "$MODULE_CONF" "SELECTOR_MODE" "urltest")"

  # 必须已选择节点且文件存在
  [ -n "$CUR_OUTBOUND_CONFIG" ] || die "CURRENT_CONFIG 未定义，请先选择节点"
  require_file "$CUR_OUTBOUND_CONFIG" "当前节点配置文件不存在: $CUR_OUTBOUND_CONFIG"

  # 解析节点所在目录
  CUR_OUTBOUND_DIR="${CUR_OUTBOUND_CONFIG%/*}"
  [ "$CUR_OUTBOUND_DIR" != "$CUR_OUTBOUND_CONFIG" ] || die "无法解析当前节点目录: $CUR_OUTBOUND_CONFIG"
  require_dir "$CUR_OUTBOUND_DIR" "当前节点目录不存在: $CUR_OUTBOUND_DIR"

  # 读取当前节点标签
  CUR_CURRENT_TAG="$(detect_outbound_tag "$CUR_OUTBOUND_CONFIG" || true)"
  [ -n "$CUR_CURRENT_TAG" ] || die "无法读取当前节点标签: $CUR_OUTBOUND_CONFIG"

  RUNTIME_OUTBOUNDS_FILE="$RUNTIME_DIR/outbounds.json"
}

#######################################
# 清空节点扫描结果缓存
# 参数: 无
# 返回: 无
#######################################
reset_runtime_nodes() {
  RUNTIME_NODE_PATHS=""
  RUNTIME_NODE_TAGS_JSON=""
  RUNTIME_NODE_COUNT=0
  RUNTIME_SKIPPED_COUNT=0
}

#######################################
# 扫描节点目录，收集节点路径与标签
# 参数:
#   $1  节点目录 (默认 CUR_OUTBOUND_DIR)
# 全局: 填充 RUNTIME_NODE_PATHS/RUNTIME_NODE_TAGS_JSON/RUNTIME_NODE_COUNT/RUNTIME_SKIPPED_COUNT
# 返回: 无
#######################################
scan_runtime_nodes() {
  local current_dir="${1:-$CUR_OUTBOUND_DIR}"
  require_dir "$current_dir" "节点目录不存在: $current_dir"
  reset_runtime_nodes

  local parsed_data
  # 用 awk 提取每个文件的首个 tag，输出 "文件名<TAB>标签"
  # (依赖 awk 的 nextfile 扩展)
  parsed_data=$(awk -F'"' '
    # 每个新文件开始时重置标志位
    FNR == 1 { found = 0 }

    # 匹配含有 "tag": "xxx" 的行
    !found && /"tag"[ \t]*:/ {
        tag = $4

        # 输出 文件名[TAB]标签
        printf "%s\t%s\n", FILENAME, tag

        # 标记已找到，跳过该文件后续行
        found = 1
        nextfile
    }
  ' "$current_dir"/*.json 2>/dev/null)

  # 未解析到任何数据则直接返回
  [ -z "$parsed_data" ] && return

  # 逐行读取 awk 结果，累积节点路径与标签
  local file tag
  while IFS="$TAB" read -r file tag; do
    # 标签为空的记录计入跳过
    if [ -z "$tag" ]; then
      RUNTIME_SKIPPED_COUNT=$((RUNTIME_SKIPPED_COUNT + 1))
      continue
    fi

    # 追加节点路径，并将非保留标签拼入 JSON 数组片段
    if [ -n "$RUNTIME_NODE_PATHS" ]; then
      RUNTIME_NODE_PATHS="${RUNTIME_NODE_PATHS}${NL}${file}"

      if ! is_reserved_outbound_tag "$tag"; then
        RUNTIME_NODE_TAGS_JSON="${RUNTIME_NODE_TAGS_JSON}, \"$tag\""
      fi
    else
      RUNTIME_NODE_PATHS="$file"

      if ! is_reserved_outbound_tag "$tag"; then
        RUNTIME_NODE_TAGS_JSON="\"$tag\""
      fi
    fi

    RUNTIME_NODE_COUNT=$((RUNTIME_NODE_COUNT + 1))
  done << EOF
$parsed_data
EOF

  # 统计目录内文件总数，反推被跳过 (无 tag) 的数量
  local total_files=0 _f
  for _f in "$current_dir"/*.json; do
    [ -e "$_f" ] && total_files=$((total_files + 1))
  done
  RUNTIME_SKIPPED_COUNT=$((total_files - RUNTIME_NODE_COUNT))
}

#######################################
# 生成运行时出站配置文件 (outbounds.json)
# 参数:
#   $1  当前节点配置路径 (默认 CUR_OUTBOUND_CONFIG)
#   $2  选择模式 (默认 CUR_SELECTOR_MODE)
# 返回: 标准输出打印输出文件路径；无可用标签或未知模式则退出
#######################################
write_runtime_outbounds() {
  local current_config="${1:-$CUR_OUTBOUND_CONFIG}"
  local selector_mode="${2:-$CUR_SELECTOR_MODE}"
  local tags="$RUNTIME_NODE_TAGS_JSON"

  [ -n "$current_config" ] || die "当前节点配置未初始化"
  [ -n "$selector_mode" ] || selector_mode="urltest"

  # 尚未扫描节点时先执行一次扫描
  if [ "$RUNTIME_NODE_COUNT" -eq 0 ] && [ -z "$RUNTIME_NODE_PATHS" ]; then
    scan_runtime_nodes "$CUR_OUTBOUND_DIR"
    tags="$RUNTIME_NODE_TAGS_JSON"
  fi

  # 扫描无标签时，回退使用当前节点标签 (非保留标签)
  if [ -z "$tags" ] && ! is_reserved_outbound_tag "$CUR_CURRENT_TAG"; then
    tags="\"$CUR_CURRENT_TAG\""
  fi

  [ -n "$tags" ] || die "当前节点目录没有可用的出站标签: $CUR_OUTBOUND_DIR"

  # 按选择模式生成对应结构的出站配置
  case "$selector_mode" in
    urltest | auto | 动态测速)
      # 动态测速模式：额外生成 Auto-Fastest 自动测速组
      cat > "$RUNTIME_OUTBOUNDS_FILE" << EOF
{
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
    },
    {
      "tag": "proxy",
      "type": "selector",
      "outbounds": [
        "Auto-Fastest",
        "direct",
        $tags
      ],
      "default": "Auto-Fastest",
      "interrupt_exist_connections": true
    },
    {
      "tag": "Auto-Fastest",
      "type": "urltest",
      "outbounds": [
        $tags
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "3m",
      "tolerance": 50
    }
  ]
}
EOF
      ;;
    manual | selector | 手动选择 | 手动)
      # 手动选择模式：仅生成 selector，默认指向当前节点
      cat > "$RUNTIME_OUTBOUNDS_FILE" << EOF
{
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
    },
    {
      "tag": "proxy",
      "type": "selector",
      "outbounds": [
        "direct",
        $tags
      ],
      "default": "$CUR_CURRENT_TAG",
      "interrupt_exist_connections": true
    }
  ]
}
EOF
      ;;
    *)
      die "未知节点选择模式: $selector_mode"
      ;;
  esac

  # 输出生成的配置文件路径
  printf "%s\n" "$RUNTIME_OUTBOUNDS_FILE"
}