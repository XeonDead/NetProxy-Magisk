#!/system/bin/sh
#######################################
# 文件: uninstall.sh
# 功能: 模块卸载清理脚本，由 Magisk/KernelSU/APatch 在卸载模块时执行，
#       清理安装期间部署到模块目录之外的文件 (驱动目录与 ipset 软链接)。
# 用法: 由管理器在卸载时自动调用，无需手动执行。
#######################################

# 清理集成的 IPSET 驱动目录
rm -rf "/data/adb/netfilter"

# 清理 KernelSU / APatch bin 目录下的 ipset 软链接
rm -f "/data/adb/ksu/bin/ipset"
rm -f "/data/adb/ap/bin/ipset"
