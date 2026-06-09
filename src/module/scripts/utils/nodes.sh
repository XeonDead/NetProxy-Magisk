#!/system/bin/sh
#######################################
# 文件: nodes.sh
# 功能: 节点与订阅辅助函数，提供节点文件识别、出站标签解析、
#       订阅目录/元数据管理、节点扫描与查找等能力。
# 用法: 由其他脚本通过 . "$MODDIR/scripts/utils/nodes.sh" 引入。
#       依赖 common.sh 提供的 json_escape/die 等函数。
#######################################

readonly NODE_RECORD_DELIM="$(printf '\t')"  # 扫描记录的字段分隔符 (制表符)

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
    # 回退为目录名 (参数展开取末段，等价 basename)
    printf "%s\n" "${sub_dir##*/}"
  fi
}

#######################################
# 扫描单个目录中的节点并写入结果文件
# 单次 awk 遍历目录内全部节点文件，逐行输出
# "路径 文件名 标签 来源 是否当前" (制表符分隔)。
# 参数:
#   $1  节点目录
#   $2  当前节点路径 (用于标记)
#   $3  来源标识
#   $4  输出文件
#   $5  追加模式 (1=追加，否则覆盖，默认覆盖)
# 返回: 无
#######################################
scan_nodes_in_dir() {
  local dir="$1"
  local current_config="$2"
  local source="$3"
  local output_file="$4"
  local append_mode="${5:-0}"

  # 非追加模式先清空输出文件
  [ "$append_mode" = "1" ] || : > "$output_file"

  # 单次 awk 提取各文件首个 tag 并组装记录；无 tag 文件与 _meta.json 自动跳过
  awk -v src="$source" -v cur="$current_config" '
    # 进入新文件时重置标志并取出文件名 (basename)
    FNR == 1 { found = 0; fn = FILENAME; base = fn; sub(/.*\//, "", base) }

    # 跳过订阅元数据文件
    base == "_meta.json" { nextfile }

    # 匹配到首个 "tag": "..." 即提取并输出
    !found {
      if (match($0, /"tag"[ \t]*:[ \t]*"/)) {
        rest = substr($0, RSTART + RLENGTH)
        q = index(rest, "\"")                       # 取到下一个引号为止
        tag = (q > 0) ? substr(rest, 1, q - 1) : rest
        is_current = (fn == cur) ? 1 : 0
        printf "%s\t%s\t%s\t%s\t%s\n", fn, base, tag, src, is_current
        found = 1
        nextfile
      }
    }
  ' "$dir"/*.json 2> /dev/null >> "$output_file"
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

  # 清空输出文件
  : > "$output_file"

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
