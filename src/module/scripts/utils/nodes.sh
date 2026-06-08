#!/system/bin/sh
#######################################
# 文件: nodes.sh
# 功能: 节点与订阅辅助函数，提供节点文件识别、出站标签解析、
#       订阅目录/元数据管理、节点扫描与查找等能力。
# 用法: 由其他脚本通过 . "$MODDIR/scripts/utils/nodes.sh" 引入。
#       依赖 common.sh 提供的 json_escape/die 等函数。
#######################################

readonly NODE_RECORD_DELIM="$(printf '\t')"  # 扫描记录的字段分隔符 (制表符)
NODE_SCAN_VALID_COUNT=0                       # 最近一次扫描的有效节点数
NODE_SCAN_SKIPPED_COUNT=0                     # 最近一次扫描跳过的文件数

#######################################
# 判断文件是否为节点配置文件
# 参数:
#   $1  文件路径
# 返回: 0=是节点文件，非 0=否 (不存在或为 _meta.json)
#######################################
is_node_config_file() {
  local file="$1"

  [ -f "$file" ] || return 1
  # 排除订阅元数据文件
  [ "${file##*/}" != "_meta.json" ] || return 1
}

#######################################
# 读取节点配置中的出站标签
# 参数:
#   $1  节点配置文件路径
# 返回: 标准输出打印首个 tag 值；文件不存在返回非 0
#######################################
detect_outbound_tag() {
  local config_file="$1"

  [ -f "$config_file" ] || return 1
  # 匹配到首个 "tag" 字段即打印其值并退出
  sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p;/"tag"[[:space:]]*:/q' "$config_file" 2> /dev/null
}

#######################################
# 判断是否为选择器保留标签
# 参数:
#   $1  标签名
# 返回: 0=保留标签，非 0=普通节点标签
#######################################
is_reserved_outbound_tag() {
  case "$1" in
    direct | block | Proxy | Auto-Fastest) return 0 ;;
    *) return 1 ;;
  esac
}

#######################################
# 清理订阅名称中的非法字符 (替换为下划线)
# 参数:
#   $1  原始订阅名
# 返回: 标准输出打印清理后的名称
#######################################
sanitize_subscription_name() {
  printf "%s" "$1" | sed 's/[\/\\:*?"<>| ]/_/g'
}

#######################################
# 根据订阅名生成订阅目录路径
# 参数:
#   $1  outbounds 目录
#   $2  订阅名
# 返回: 标准输出打印订阅目录路径 (形如 .../sub_名称)
#######################################
subscription_dir_from_name() {
  local outbounds_dir="$1"
  local name="$2"

  printf "%s/sub_%s\n" "$outbounds_dir" "$(sanitize_subscription_name "$name")"
}

#######################################
# 读取订阅元数据中指定字段的值
# 参数:
#   $1  元数据文件路径 (_meta.json)
#   $2  字段名
# 返回: 标准输出打印字段值；文件不存在返回非 0
#######################################
read_subscription_meta_value() {
  local meta_file="$1"
  local key="$2"

  [ -f "$meta_file" ] || return 1
  # 提取 "key": "value" 中的 value 部分
  grep -o '"'$key'"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_file" 2> /dev/null | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

#######################################
# 写入订阅元数据文件 (_meta.json)
# 参数:
#   $1  目标订阅目录
#   $2  订阅名
#   $3  订阅链接
#   $4  请求 User-Agent (可选)
#   $5  请求 HWID (可选)
# 返回: 无 (生成 _meta.json 文件)
#######################################
write_subscription_meta() {
  local target_dir="$1"
  local name="$2"
  local url="$3"
  local ua="${4:-}"
  local hwid_val="${5:-}"
  local extra=""

  # UA 非空则追加到额外字段
  if [ -n "$ua" ]; then
    extra="$extra
  \"ua\": \"$(json_escape "$ua")\","
  fi

  # HWID 非空则追加到额外字段
  if [ -n "$hwid_val" ]; then
    extra="$extra
  \"hwid\": \"$(json_escape "$hwid_val")\","
  fi

  # 写出元数据，updated 记录当前时间
  cat > "$target_dir/_meta.json" << EOF
{
  "name": "$(json_escape "$name")",
  "url": "$(json_escape "$url")",${extra}
  "updated": "$(date -Iseconds)"
}
EOF
}

#######################################
# 获取订阅的显示名称
# 参数:
#   $1  订阅目录
# 返回: 标准输出打印元数据中的 name，缺失时回退为目录名
#######################################
subscription_display_name() {
  local sub_dir="$1"
  local meta_file="$sub_dir/_meta.json"
  local name

  name="$(read_subscription_meta_value "$meta_file" "name" 2> /dev/null || true)"
  if [ -n "$name" ]; then
    printf "%s\n" "$name"
  else
    printf "%s\n" "$(basename "$sub_dir")"
  fi
}

#######################################
# 重置节点扫描计数器
# 参数: 无
# 返回: 无
#######################################
reset_node_scan_counters() {
  NODE_SCAN_VALID_COUNT=0
  NODE_SCAN_SKIPPED_COUNT=0
}

#######################################
# 向扫描结果文件追加一条节点记录
# 参数:
#   $1  输出文件
#   $2  节点文件路径
#   $3  出站标签
#   $4  来源 (默认节点 / 订阅名)
#   $5  是否当前节点 (1=是)
# 返回: 无 (追加一行 制表符分隔 记录)
#######################################
append_node_record() {
  local output_file="$1"
  local file="$2"
  local tag="$3"
  local source="$4"
  local is_current="$5"

  printf "%s\t%s\t%s\t%s\t%s\n" "$file" "$(basename "$file")" "$tag" "$source" "$is_current" >> "$output_file"
}

#######################################
# 扫描单个目录中的节点并写入结果文件
# 参数:
#   $1  节点目录
#   $2  当前节点路径 (用于标记)
#   $3  来源标识
#   $4  输出文件
#   $5  追加模式 (1=追加，否则覆盖，默认覆盖)
# 返回: 无 (更新 NODE_SCAN_* 计数器)
#######################################
scan_nodes_in_dir() {
  local dir="$1"
  local current_config="$2"
  local source="$3"
  local output_file="$4"
  local append_mode="${5:-0}"
  local file tag is_current

  # 非追加模式则清空输出文件并重置计数
  if [ "$append_mode" != "1" ]; then
    : > "$output_file"
    reset_node_scan_counters
  fi

  # 遍历目录下所有 json 节点文件
  for file in "$dir"/*.json; do
    is_node_config_file "$file" || continue
    tag="$(detect_outbound_tag "$file" || true)"

    # 无法解析标签的文件计入跳过
    if [ -z "$tag" ]; then
      NODE_SCAN_SKIPPED_COUNT=$((NODE_SCAN_SKIPPED_COUNT + 1))
      continue
    fi

    # 标记是否为当前使用的节点
    is_current=0
    [ "$file" = "$current_config" ] && is_current=1
    append_node_record "$output_file" "$file" "$tag" "$source" "$is_current"
    NODE_SCAN_VALID_COUNT=$((NODE_SCAN_VALID_COUNT + 1))
  done
}

#######################################
# 扫描全部节点 (默认目录 + 所有订阅目录)
# 参数:
#   $1  outbounds 目录
#   $2  当前节点路径
#   $3  输出文件
# 返回: 无 (结果写入输出文件)
#######################################
scan_all_nodes() {
  local outbounds_dir="$1"
  local current_config="$2"
  local output_file="$3"
  local sub_dir source

  # 清空输出文件并重置计数
  : > "$output_file"
  reset_node_scan_counters

  # 先扫描默认节点目录
  scan_nodes_in_dir "$outbounds_dir/default" "$current_config" "默认节点" "$output_file" 1

  # 再逐个扫描各订阅目录
  for sub_dir in "$outbounds_dir"/sub_*; do
    [ -d "$sub_dir" ] || continue
    source="订阅: $(subscription_display_name "$sub_dir")"
    scan_nodes_in_dir "$sub_dir" "$current_config" "$source" "$output_file" 1
  done
}

#######################################
# 从扫描结果中读取当前节点路径
# 参数:
#   $1  扫描结果文件
# 返回: 标准输出打印当前节点路径；无当前节点返回非 0
#######################################
find_current_node_from_scan() {
  local scan_file="$1"
  local path name tag source is_current

  # 逐行查找标记为当前的记录
  while IFS="$NODE_RECORD_DELIM" read -r path name tag source is_current; do
    [ "$is_current" = "1" ] || continue
    printf "%s\n" "$path"
    return 0
  done < "$scan_file"

  return 1
}

#######################################
# 根据查询条件解析出唯一节点路径
# 参数:
#   $1  扫描结果文件
#   $2  查询条件 (路径 / 文件名 / 去后缀名 / 标签)
# 返回: 标准输出打印匹配到的节点路径；无匹配或多匹配则退出
#######################################
resolve_node_from_scan() {
  local scan_file="$1"
  local query="$2"
  local match_count=0
  local first_match=""
  local path name tag source is_current base

  [ -n "$query" ] || die "请指定节点名称、标签或路径"

  # 查询条件本身就是有效文件路径时直接返回
  if [ -f "$query" ]; then
    printf "%s\n" "$query"
    return 0
  fi

  # 逐行匹配路径/文件名/去后缀名/标签
  while IFS="$NODE_RECORD_DELIM" read -r path name tag source is_current; do
    base="${name%.json}"

    if [ "$query" = "$path" ] || [ "$query" = "$name" ] || [ "$query" = "$base" ] || [ "$query" = "$tag" ]; then
      match_count=$((match_count + 1))
      [ "$match_count" -eq 1 ] && first_match="$path"
    fi
  done < "$scan_file"

  # 根据匹配数量决定返回或报错
  case "$match_count" in
    0)
      die "未找到节点: $query"
      ;;
    1)
      printf "%s\n" "$first_match"
      ;;
    *)
      die "找到多个同名节点，请使用更精确的文件名或完整路径"
      ;;
  esac
}
