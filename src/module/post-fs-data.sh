#!/system/bin/sh
#######################################
# 文件: post-fs-data.sh
# 功能: Magisk post-fs-data 阶段入口，在文件系统挂载后、系统启动前执行，
#       负责加载 IPSET 内核驱动 (供后续透明代理的 ipset 规则使用)。
# 用法: 由 Magisk/KernelSU/APatch 在 post-fs-data 阶段自动调用。
#######################################

set -e  # 命令失败立即退出

# 模块根目录与关键路径
readonly MODDIR="${0%/*}"                          # 模块根目录 (脚本所在目录)
readonly MODULE_CONF="$MODDIR/config/module.conf"  # 模块配置
readonly LOG_FILE="$MODDIR/logs/service.log"       # 服务日志
readonly LOG_TAG="post-fs"                         # 日志组件标签

. "$MODDIR/scripts/utils/common.sh"

log "INFO" "post-fs-data 阶段"

# 加载集成的 IPSET 内核驱动
sh "$MODDIR/scripts/utils/ipset.sh" load
