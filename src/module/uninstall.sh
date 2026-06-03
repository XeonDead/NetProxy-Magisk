#!/system/bin/sh
# NetProxy 卸载清理脚本

# 1. 清理 IPSET 驱动目录
rm -rf "/data/adb/netfilter"

# 2. 清理 KernelSU/APatch 中的 ipset 软链接
rm -f "/data/adb/ksu/bin/ipset"
rm -f "/data/adb/ap/bin/ipset"
