## 版本 7.0.2（2026-05-28）

### 主要变更

1. 性能模式与网络路由优化：
   * 默认开启性能模式（`tproxy.conf` 中 `PERFORMANCE_MODE=1`）。
   * 修复了部分设备在 Wi-Fi 环境下开启性能模式后代理问题

2. 节点解析与转换优化 (Proxylink 内核升级)：
   * 新增 Shadowsocks 插件 (`plugin`) 及参数 (`plugin-opts`) 的解析与转换支持
   * 修复节点 `tag` 标签中类似 `>` 等特殊符号在生成 JSON 时被 HTML 转义为 `\u003e` 导致引用不一致的问题。
   * 空 `fp` (fingerprint) 参数时，节点转换将默认回退并应用 `chrome` 客户端指纹。

3. 配置及清理：
   * 移除内置的 `default.json` 节点，并且默认将 `CURRENT_CONFIG` 置空。
   * 不再将 `default` 词条列为保留出站标签，防止命名冲突导致的过滤问题。

4. 组件更新：
   * `sing-box` 更新至 **1.14.0-alpha.26-reF1nd**
   * `zashboard` 更新至 **v3.6.0**
   * `AndroidTProxyShell` 更新至 **v26.05.28**


* * *
