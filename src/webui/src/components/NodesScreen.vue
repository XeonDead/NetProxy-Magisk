<script setup lang="ts">
/**
 * @file NodesScreen.vue
 * @description 节点页：按分组（默认/订阅/自定义）管理 sing-box 节点。支持标签页/列表两种布局、
 *   排序与密度、节点切换、单点/整组测速（活动组用主 Clash API，非活动组临时拉起 19999 实例离线测）、
 *   导入（剪贴板/文件/链接/订阅）、增删分组与节点、编辑节点 JSON。长列表用自建虚拟滚动。
 *   非真机环境用 mock 数据（含 1000 节点大订阅以验证虚拟滚动）。
 */
import { ref, computed, onMounted, onActivated, onDeactivated, onUnmounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { showToast, readFileContent, writeFileContent, isKsuEnv, execAsync } from '../utils/ksu';
import { useBackDismiss } from '../composables/useBackDismiss';

const { t } = useI18n();

/** 配置分组：默认 / 订阅 / 自定义，含其下的节点文件名列表。 */
interface ConfigGroup {
  name: string;
  dirName: string;
  type: 'default' | 'subscription' | 'custom';
  configs: string[]; // 该分组目录下的配置文件名
}

/** 节点运行期数据：标签 / 协议 / 延迟 / 是否测速中。 */
interface NodeData {
  tag: string;
  protocol: string;
  latency: string;
  testing: boolean;
}

const isKsu = isKsuEnv();

// 从系统加载的配置分组
const configGroups = ref<ConfigGroup[]>([]);
const selectedGroupDirName = ref<string>('');
const isLoading = ref(false);

// 节点详情字典，键为 "分组目录/配置文件名"
const allNodes = ref<Record<string, NodeData>>({});
const currentConfigPath = ref<string>('');

// Clash API 连接配置
const apiHost = ref('127.0.0.1:9999');
const apiSecret = ref('singbox');

// 持久化到 localStorage 的界面偏好
const nodeSortType = ref<'default' | 'latency' | 'name'>(
  (localStorage.getItem('node_sort_type') as any) || 'default'
);
const nodeLayoutDensity = ref<'loose' | 'standard' | 'compact'>(
  (localStorage.getItem('node_layout_density') as any) || 'standard'
);
const nodeItemSize = ref<'standard' | 'compact' | 'minimal'>(
  (localStorage.getItem('node_item_size') as any) || 'standard'
);
// 布局样式：tab=顶部分组标签栏+当前组网格；list=分组纵向可折叠
const nodeLayoutStyle = ref<'tab' | 'list'>(
  (localStorage.getItem('node_layout_style') as any) || 'tab'
);

watch(nodeSortType, (val) => localStorage.setItem('node_sort_type', val));
watch(nodeLayoutDensity, (val) => localStorage.setItem('node_layout_density', val));
watch(nodeItemSize, (val) => localStorage.setItem('node_item_size', val));
watch(nodeLayoutStyle, (val) => {
  localStorage.setItem('node_layout_style', val);
  // 切到列表模式且没有任何展开项时，默认展开当前组，避免页面看起来空白
  if (val === 'list' && expandedGroups.value.size === 0 && selectedGroupDirName.value) {
    expandedGroups.value = new Set([selectedGroupDirName.value]);
    localStorage.setItem('node_expanded_groups', JSON.stringify([selectedGroupDirName.value]));
  }
});

// 列表模式下各分组的展开态 (按 dirName)
const expandedGroups = ref<Set<string>>(new Set(
  JSON.parse(localStorage.getItem('node_expanded_groups') || '[]')
));
const toggleGroup = (dirName: string) => {
  const next = new Set(expandedGroups.value);
  if (next.has(dirName)) next.delete(dirName); else next.add(dirName);
  expandedGroups.value = next;
  localStorage.setItem('node_expanded_groups', JSON.stringify([...next]));
};

// 各弹窗/菜单的开关状态
const showDisplaySettingsDialog = ref(false);
const showMenu = ref(false);
const showAddSubDialog = ref(false);
const showCreateGroupDialog = ref(false);
const showNodeActionDialog = ref(false);
const showEditDialog = ref(false);

// 是否有任意弹窗/菜单打开（返回手势拦截与下拉刷新屏蔽共用）
const anyDialogOpen = () =>
  showDisplaySettingsDialog.value || showMenu.value || showAddSubDialog.value
  || showCreateGroupDialog.value || showNodeActionDialog.value || showEditDialog.value;

// 手势返回优先关闭弹窗（而非退出页面）
useBackDismiss(
  anyDialogOpen,
  () => {
    showDisplaySettingsDialog.value = false;
    showMenu.value = false;
    showAddSubDialog.value = false;
    showCreateGroupDialog.value = false;
    showNodeActionDialog.value = false;
    showEditDialog.value = false;
  }
);

// 表单绑定
const subName = ref('');
const subUrl = ref('');
const subUa = ref('');
const subHwid = ref('');
const newGroupName = ref('');
const selectedActionNode = ref<string | null>(null); // 配置文件名（如 node1.json）
const editingContent = ref('');

// 下拉刷新状态
const pullDelta = ref(0);
const isRefreshing = ref(false);
const refreshText = computed(() => {
  if (isRefreshing.value) return t('nodes.refreshing');
  if (pullDelta.value > 50) return t('nodes.releaseToRefresh');
  return t('nodes.pullToRefresh');
});

let touchStartY = 0;
let isPulling = false;

/** 触摸开始：仅在列表顶部、无弹窗、未刷新时进入下拉判定。 */
const handleTouchStart = (e: TouchEvent) => {
  // 弹窗/菜单打开时不触发下拉刷新
  if (anyDialogOpen()) return;
  const container = document.querySelector('.page-scroller');
  if (!container || container.scrollTop > 0 || isRefreshing.value) return;
  touchStartY = e.touches[0].clientY;
  isPulling = true;
};

/** 触摸移动：按阻尼累计下拉距离，超过阈值时阻止默认滚动。 */
const handleTouchMove = (e: TouchEvent) => {
  if (!isPulling || isRefreshing.value) return;
  const currentY = e.touches[0].clientY;
  const delta = currentY - touchStartY;
  if (delta > 0) {
    pullDelta.value = Math.min(80, delta * 0.45);
    if (pullDelta.value > 0) {
      e.preventDefault();
    }
  }
};

/** 触摸结束：下拉超过阈值则重载节点并整组测速，否则回弹。 */
const handleTouchEnd = () => {
  if (!isPulling) return;
  isPulling = false;
  if (pullDelta.value > 50) {
    isRefreshing.value = true;
    pullDelta.value = 50;
    setTimeout(async () => {
      await loadNodes();
      testAllLatency(true);
      isRefreshing.value = false;
      pullDelta.value = 0;
      showToast(t('nodes.refreshDone'));
    }, 500);
  } else {
    pullDelta.value = 0;
  }
};

// 长按处理：按住 600ms 触发节点操作弹窗
let pressTimer: any = null;
let isLongPress = false;

/** 开始长按计时（600ms 后弹出节点操作菜单）。 */
const startPress = (filename: string) => {
  isLongPress = false;
  pressTimer = setTimeout(() => {
    isLongPress = true;
    handleLongClickNode(filename);
  }, 600);
};

/** 取消长按计时。 */
const endPress = () => {
  if (pressTimer) {
    clearTimeout(pressTimer);
    pressTimer = null;
  }
};

// 隐藏的文件选择 input 引用
const fileInputRef = ref<HTMLInputElement | null>(null);

// 计算属性

/** 当前选中分组对象（无则 null）。 */
const activeGroup = computed(() => {
  return configGroups.value.find(g => g.dirName === selectedGroupDirName.value) || null;
});

// 延迟数值化 (用于排序)
const getLatencyNumber = (latencyStr?: string): number => {
  if (!latencyStr) return 999999;
  if (latencyStr === 'timeout' || latencyStr === 'failed') return 999999;
  if (latencyStr.includes('testing...')) return 999998;
  const num = parseInt(latencyStr.replace(/[^0-9]/g, ''));
  return isNaN(num) ? 999997 : num;
};

// 延迟颜色 (绿/橙/红/灰)
const latencyColor = (latencyVal?: string): string => {
  if (!latencyVal || latencyVal === 'testing...') return 'rgba(128, 128, 128, 0.5)';
  if (latencyVal === 'timeout' || latencyVal === 'failed') return '#F44336';
  const ms = parseInt(latencyVal.replace(/[^0-9]/g, ''));
  if (isNaN(ms)) return '#F44336';
  if (ms < 100) return '#4CAF50';
  if (ms < 300) return '#FF9800';
  return '#F44336';
};

// 延迟显示文案
const latencyText = (lat: string): string => {
  if (lat === 'testing...') return t('nodes.testing');
  if (lat === 'timeout') return t('nodes.timeout');
  if (lat === 'failed') return t('nodes.testFailed');
  return lat;
};

/** 视图节点：一次性算好排序与展示属性（延迟文案/颜色、是否当前），模板直接读。 */
interface ViewNode {
  key: string;        // 相对路径，稳定 key
  filename: string;
  tag: string;
  protocol: string;
  hasLatency: boolean;
  latencyText: string;
  latencyColor: string;
  isCurrent: boolean;
}

/**
 * 为指定分组目录构建已排序的视图节点（标签页/列表模式共用）。
 * @param dir      分组目录名
 * @param configs  该组配置文件名列表
 * @returns 排序并装饰后的视图节点数组
 */
const buildGroupViewNodes = (dir: string, configs: string[]): ViewNode[] => {
  const dict = allNodes.value;
  const current = currentConfigPath.value;

  // decorate：预取 node，避免比较器内重复查字典
  const decorated = configs.map((filename) => ({
    filename,
    node: dict[`${dir}/${filename}`]
  }));

  // sort
  if (nodeSortType.value === 'name') {
    decorated.sort((a, b) => (a.node?.tag || '').localeCompare(b.node?.tag || ''));
  } else if (nodeSortType.value === 'latency') {
    decorated.sort((a, b) => getLatencyNumber(a.node?.latency) - getLatencyNumber(b.node?.latency));
  }

  // build view objects
  return decorated.map(({ filename, node }) => {
    const lat = node?.latency || '';
    return {
      key: `${dir}/${filename}`,
      filename,
      tag: node?.tag || filename.replace('.json', ''),
      protocol: node?.protocol || 'VMESS',
      hasLatency: !!lat,
      latencyText: latencyText(lat),
      latencyColor: latencyColor(lat),
      isCurrent: current === `${dir}/${filename}`
    };
  });
};

/** 当前组的视图节点（标签页模式用）。 */
const viewNodes = computed<ViewNode[]>(() => {
  const group = activeGroup.value;
  if (!group) return [];
  return buildGroupViewNodes(selectedGroupDirName.value, group.configs);
});

// ===================================================================
// 数据加载（API 配置 / 节点列表）
// ===================================================================

/** 从 02_experimental.json 读取 Clash API 的 external_controller/secret（0.0.0.0 改写为 127.0.0.1）。 */
const loadApiConfig = async () => {
  if (!isKsu) return;
  try {
    const content = await readFileContent('/data/adb/modules/netproxy/config/singbox/confdir/02_experimental.json');
    const jsonObj = JSON.parse(content);
    const clashApi = jsonObj?.experimental?.clash_api;
    let host = clashApi?.external_controller || '127.0.0.1:9999';
    const secret = clashApi?.secret || 'singbox';
    if (host.startsWith('0.0.0.0:')) {
      host = '127.0.0.1:' + host.substring(8);
    } else if (host === '0.0.0.0') {
      host = '127.0.0.1:9999';
    }
    apiHost.value = host;
    apiSecret.value = secret;
  } catch (e) {
    console.warn('Failed to read API config:', e);
  }
};

/** 探测主服务是否在运行（300ms 超时请求 Clash API /configs）。 */
const checkMainServiceRunning = async (): Promise<boolean> => {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 300);
    const res = await fetch(`http://${apiHost.value}/configs`, {
      headers: { 'Authorization': `Bearer ${apiSecret.value}` },
      signal: controller.signal
    });
    clearTimeout(timer);
    return res.ok;
  } catch {
    return false;
  }
};

/** 加载全部分组与节点：真机用单次 shell（零 fork 解析 _meta.json、awk 提取 tag/protocol），mock 生成大数据集。 */
const loadNodes = async () => {
  isLoading.value = true;
  await new Promise(resolve => setTimeout(resolve, 50));
  try {
    if (!isKsu) {
      // 开发用 mock 配置（带模拟延迟）
      await new Promise(resolve => setTimeout(resolve, 300));

      // 生成 1000 个节点的大订阅，用于验证虚拟滚动性能
      const regions = ['香港-HK', '新加坡-SG', '日本-JP', '美国-US', '德国-DE', '英国-UK', '韩国-KR', '台湾-TW'];
      const protocols = ['VMESS', 'VLESS', 'TROJAN', 'SHADOWSOCKS'];
      const bigConfigs: string[] = [];
      const bigNodes: Record<string, NodeData> = {};
      for (let i = 1; i <= 1000; i++) {
        const fn = `node${i}.json`;
        bigConfigs.push(fn);
        const region = regions[i % regions.length];
        bigNodes[`sub_big/${fn}`] = {
          tag: `${region}-${String(i).padStart(4, '0')}`,
          protocol: protocols[i % protocols.length],
          latency: i % 3 === 0 ? `${40 + (i % 260)} ms` : '',
          testing: false
        };
      }

      configGroups.value = [
        { name: '默认分组', dirName: 'default', type: 'default', configs: ['node_direct.json'] },
        { name: '超大订阅(1000)', dirName: 'sub_big', type: 'subscription', configs: bigConfigs },
        { name: '备用游戏专线', dirName: 'sub_gaming', type: 'subscription', configs: ['node5.json', 'node6.json'] }
      ];
      selectedGroupDirName.value = 'sub_big';
      allNodes.value = {
        'default/node_direct.json': { tag: '直连节点', protocol: 'DIRECT', latency: '', testing: false },
        'sub_gaming/node5.json': { tag: '美国-US-01 [LowLatency]', protocol: 'SHADOWSOCKS', latency: '168 ms', testing: false },
        'sub_gaming/node6.json': { tag: '德国-DE-01 [Backup]', protocol: 'VMESS', latency: '220 ms', testing: false },
        ...bigNodes
      };
      currentConfigPath.value = 'sub_big/node2.json';
      return;
    }

    const outboundsDir = '/data/adb/modules/netproxy/config/singbox/outbounds';
    const cmd = [
      'outbounds_dir="' + outboundsDir + '"',
      'module_conf="/data/adb/modules/netproxy/config/module.conf"',
      '',
      '# 1. Print current active config',
      'if [ -f "$module_conf" ]; then',
      '  curr="$(grep -E \'^CURRENT_CONFIG=\' "$module_conf" | cut -d= -f2-)"',
      '  curr="${curr#\\\"}"',
      '  curr="${curr%\\\"}"',
      '  curr="${curr#\\\'}"',
      '  curr="${curr%\\\'}"',
      '  curr="${curr#$outbounds_dir/}"',
      '  printf "CURRENT\\t%s\\n" "$curr"',
      'fi',
      '',
      '# 2. Print all group folders and list config files',
      'for d in "$outbounds_dir"/*; do',
      '  [ -d "$d" ] || continue',
      '  dirname="${d##*/}"',
      '  if [ "$dirname" = "default" ]; then',
      '    printf "GROUP\\tdefault\\tdefault\\tdefault\\n"',
      '  elif [ "${dirname#sub_}" != "$dirname" ]; then',
      '    name=""',
      '    if [ -f "$d/_meta.json" ]; then',
      '      # Zero-fork POSIX parser for _meta.json',
      '      while read -r line || [ -n "$line" ]; do',
      '        case "$line" in',
      '          *\'"name"\'*)',
      '            val="${line#*:}"',
      '            temp="${val#*\\\"}"',
      '            name="${temp%%\\\"*}"',
      '            break',
      '            ;;',
      '        esac',
      '      done < "$d/_meta.json"',
      '    fi',
      '    [ -n "$name" ] || name="${dirname#sub_}"',
      '    printf "GROUP\\tsubscription\\t%s\\t%s\\n" "$name" "$dirname"',
      '  else',
      '    printf "GROUP\\tcustom\\t%s\\t%s\\n" "$dirname" "$dirname"',
      '  fi',
      '',
      '  for f in "$d"/*.json; do',
      '    [ -f "$f" ] || continue',
      '    fname="${f##*/}"',
      '    [ "$fname" = "_meta.json" ] && continue',
      '    # 一趟 awk 提取首个 tag 与 type/protocol，输出 FILE\\t目录\\t文件\\t标签\\t协议',
      '    awk -v d="$dirname" -v fn="$fname" \'',
      '      /"tag"[[:space:]]*:/ && tag=="" { s=$0; sub(/.*"tag"[[:space:]]*:[[:space:]]*"/, "", s); sub(/".*/, "", s); tag=s }',
      '      /"(type|protocol)"[[:space:]]*:/ && proto=="" { s=$0; sub(/.*"(type|protocol)"[[:space:]]*:[[:space:]]*"/, "", s); sub(/".*/, "", s); proto=s }',
      '      tag!="" && proto!="" { exit }',
      '      END { printf "FILE\\t%s\\t%s\\t%s\\t%s\\n", d, fn, tag, proto }\' "$f"',
      '  done',
      'done'
    ].join('\n');

    const res = await execAsync(cmd);
    if (res.errno !== 0) {
      throw new Error(res.stderr || 'Failed to list nodes');
    }

    const lines = res.stdout.split('\n').filter(Boolean);
    const groupsMap = new Map<string, ConfigGroup>();
    const nodesDict: Record<string, NodeData> = {};
    let activePath = '';

    // 第 1 步：解析分组与文件
    for (const line of lines) {
      if (line.startsWith('/')) continue;
      const parts = line.split('\t');
      if (parts.length < 2) continue;

      const action = parts[0].trim();

      if (action === 'CURRENT') {
        activePath = parts[1].trim();
      } else if (action === 'GROUP') {
        const type = parts[1].trim() as 'default' | 'subscription' | 'custom';
        const name = parts[2].trim();
        const dirName = parts[3].trim();

        groupsMap.set(dirName, {
          name: name,
          dirName: dirName,
          type: type,
          configs: []
        });
      } else if (action === 'FILE') {
        const dirName = parts[1].trim();
        const fileName = parts[2].trim();
        const tag = (parts[3] ?? '').trim();
        const protocol = (parts[4] ?? '').trim();

        // 确保分组存在
        if (!groupsMap.has(dirName)) {
          const type = dirName.startsWith('sub_') ? 'subscription' : (dirName === 'default' ? 'default' : 'custom');
          groupsMap.set(dirName, {
            name: dirName.startsWith('sub_') ? dirName.substring(4) : dirName,
            dirName: dirName,
            type: type,
            configs: []
          });
        }

        const group = groupsMap.get(dirName)!;
        if (!group.configs.includes(fileName)) {
          group.configs.push(fileName);
        }

        // tag/protocol 已由 awk 一趟提取，直接建节点数据
        nodesDict[`${dirName}/${fileName}`] = {
          tag: tag || fileName.replace('.json', ''),
          protocol: protocol ? protocol.toUpperCase() : 'UNKNOWN',
          latency: '',
          testing: false
        };
      }
    }

    // 各分组内配置按字母排序
    for (const [_, group] of groupsMap) {
      group.configs.sort();
    }

    // 分组排序：默认组置顶，其余按名称
    configGroups.value = Array.from(groupsMap.values()).sort((a, b) => {
      if (a.type === 'default') return -1;
      if (b.type === 'default') return 1;
      return a.name.localeCompare(b.name);
    });

    // tag/protocol 已随 awk 一趟取到 nodesDict，缓存供下次打开秒显
    const infoCache: Record<string, { tag: string; protocol: string }> = {};
    for (const [relativePath, data] of Object.entries(nodesDict)) {
      infoCache[relativePath] = { tag: data.tag, protocol: data.protocol };
    }
    localStorage.setItem('netproxy_nodes_info_cache', JSON.stringify(infoCache));

    allNodes.value = nodesDict;
    currentConfigPath.value = activePath;

    if (selectedGroupDirName.value === '' && configGroups.value.length > 0) {
      if (activePath) {
        selectedGroupDirName.value = activePath.split('/')[0];
      } else {
        selectedGroupDirName.value = configGroups.value[0].dirName;
      }
    }
  } catch (e) {
    console.error('Failed to load nodes:', e);
    showToast(t('nodes.loadFailed'));
  } finally {
    isLoading.value = false;
  }
};

// ===================================================================
// 节点操作：选择 / 长按 / 列表模式委托
// ===================================================================

/**
 * 选择并切换到某节点（乐观更新 UI，真机调 switch.sh，失败回滚）。
 * @param filename  节点配置文件名
 */
const handleSelectNode = async (filename: string) => {
  if (isLongPress) {
    isLongPress = false;
    return;
  }
  const relativePath = `${selectedGroupDirName.value}/${filename}`;
  const oldConfigPath = currentConfigPath.value;

  // 1. 乐观更新 UI
  currentConfigPath.value = relativePath;

  // 2. 让出线程，等 Vue 完成布局/绘制/DOM 更新
  await new Promise(resolve => setTimeout(resolve, 50));

  try {
    if (isKsu) {
      const fullPath = `/data/adb/modules/netproxy/config/singbox/outbounds/${relativePath}`;
      // 直接执行 switch.sh，绕过 cli 包装以提速
      const res = await execAsync(`sh /data/adb/modules/netproxy/scripts/core/switch.sh config "${fullPath}"`);
      if (res.errno !== 0) {
        throw new Error(res.stderr || `Switch script failed with exit status ${res.errno}`);
      }
    }
    showToast(t('nodes.switchedTo', { tag: allNodes.value[relativePath]?.tag || filename.replace('.json', '') }));
  } catch (err: any) {
    // 失败时回滚状态
    currentConfigPath.value = oldConfigPath;
    showToast(t('nodes.switchFailed', { msg: err.message || err }));
  }
};

/** 长按节点：记录目标并打开节点操作弹窗。 */
const handleLongClickNode = (filename: string) => {
  selectedActionNode.value = filename;
  showNodeActionDialog.value = true;
};

// 列表模式：操作前先把上下文切到该节点所属分组，再委托给统一处理函数
const onListSelect = (dir: string, filename: string) => {
  selectedGroupDirName.value = dir;
  handleSelectNode(filename);
};
const onListPressStart = (dir: string, filename: string) => {
  selectedGroupDirName.value = dir;
  startPress(filename);
};
const onListLatency = (dir: string, filename: string) => {
  selectedGroupDirName.value = dir;
  testNodeLatency(filename);
};

// ===================================================================
// 离线测速：临时拉起 sing-box（127.0.0.1:19999）跑 Clash delay 接口
// ===================================================================

/**
 * 为非活动组临时拉起一个仅含 direct 出站 + 待测节点的 sing-box 实例（Clash API 19999），
 * 等其就绪（最多 5s）后返回 PID 供测速使用。
 * @param groupDirName  分组目录名
 * @param configs       要载入测试的节点文件名列表
 * @returns 测试进程 PID
 * @throws 启动失败或 API 未就绪时抛出
 */
const startOfflineTestProcess = async (groupDirName: string, configs: string[]): Promise<number> => {
  await stopOfflineTestProcessInternal();

  const tempConfigPath = '/data/adb/modules/netproxy/config/singbox/runtime/latency_test.json';
  const tempConfigContent = JSON.stringify({
    log: { level: 'error' },
    dns: {
      servers: [
        { tag: 'dns-direct', type: 'udp', server: '223.5.5.5' },
        { tag: 'dns-fallback', type: 'udp', server: '119.29.29.29' }
      ],
      strategy: 'ipv4_only'
    },
    route: { default_domain_resolver: 'dns-direct' },
    outbounds: [
      { tag: 'direct', type: 'direct' }
    ],
    experimental: {
      clash_api: {
        external_controller: '127.0.0.1:19999',
        secret: 'latency_test'
      }
    }
  }, null, 2);

  await writeFileContent(tempConfigPath, tempConfigContent);

  let cmd = `nohup /data/adb/modules/netproxy/bin/sing-box run -c "${tempConfigPath}"`;
  for (const filename of configs) {
    const absPath = `/data/adb/modules/netproxy/config/singbox/outbounds/${groupDirName}/${filename}`;
    cmd += ` -c "${absPath}"`;
  }
  cmd += ` >/dev/null 2>&1 & echo $!`;

  const res = await execAsync(cmd);
  if (res.errno !== 0 || !res.stdout.trim()) {
    throw new Error('Failed to launch sing-box test process');
  }

  const pid = parseInt(res.stdout.trim());
  if (isNaN(pid) || pid <= 0) {
    throw new Error('Invalid PID returned for test process');
  }

  // 等待 Clash API 就绪（最多 5s）
  let isReady = false;
  for (let i = 0; i < 20; i++) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 200);
      const checkRes = await fetch('http://127.0.0.1:19999/configs', {
        headers: { 'Authorization': 'Bearer latency_test' },
        signal: controller.signal
      });
      clearTimeout(timer);
      if (checkRes.ok) {
        isReady = true;
        break;
      }
    } catch {
      // 忽略
    }
    await new Promise(resolve => setTimeout(resolve, 250));
  }

  if (!isReady) {
    await execAsync(`kill -9 ${pid}`);
    throw new Error('Offline Clash API did not become ready in time');
  }

  return pid;
};

/** 停止离线测试进程（先 SIGTERM 再 SIGKILL）并删除临时配置。 */
const stopOfflineTestProcess = async (pid: number) => {
  if (pid > 0) {
    await execAsync(`kill -15 ${pid}`);
    await new Promise(resolve => setTimeout(resolve, 200));
    const check = await execAsync(`kill -0 ${pid}`);
    if (check.errno === 0) {
      await execAsync(`kill -9 ${pid}`);
    }
  }
  await execAsync('rm -f /data/adb/modules/netproxy/config/singbox/runtime/latency_test.json');
};

/** 兜底清理：pkill 残留测试进程并删除临时配置。 */
const stopOfflineTestProcessInternal = async () => {
  await execAsync(`pkill -f latency_test.json || true`);
  await execAsync('rm -f /data/adb/modules/netproxy/config/singbox/runtime/latency_test.json');
};

/**
 * 测试单个节点延迟：活动组直接用主 Clash API，非活动组临时拉起离线实例测完即清理。
 * @param filename  节点配置文件名
 */
const testNodeLatency = async (filename: string) => {
  const fullPath = `${selectedGroupDirName.value}/${filename}`;
  const node = allNodes.value[fullPath];
  if (!node) return;

  node.testing = true;
  node.latency = 'testing...';

  try {
    if (isKsu) {
      // 判断是否为活动组且主服务在运行
      const isRunning = await checkMainServiceRunning();
      const activeGroupDirName = currentConfigPath.value ? currentConfigPath.value.split('/')[0] : '';
      const isActiveGroup = isRunning && activeGroupDirName && selectedGroupDirName.value === activeGroupDirName;

      let host = apiHost.value;
      let secret = apiSecret.value;
      let pid = 0;

      if (!isActiveGroup) {
        // 非活动组：仅为该节点拉起离线测试进程
        pid = await startOfflineTestProcess(selectedGroupDirName.value, [filename]);
        host = '127.0.0.1:19999';
        secret = 'latency_test';
      }

      try {
        const encodedTag = encodeURIComponent(node.tag);
        const encodedUrl = encodeURIComponent('https://www.gstatic.com/generate_204');
        const url = `http://${host}/proxies/${encodedTag}/delay?timeout=5000&url=${encodedUrl}`;
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 6000);
        const res = await fetch(url, {
          headers: { 'Authorization': `Bearer ${secret}` },
          signal: controller.signal
        });
        clearTimeout(timer);
        if (res.ok) {
          const data = await res.json();
          if (data.delay !== undefined && data.delay >= 0) {
            node.latency = `${data.delay} ms`;
          } else {
            node.latency = 'failed';
          }
        } else {
          node.latency = 'failed';
        }
      } finally {
        if (pid > 0) {
          await stopOfflineTestProcess(pid);
        }
      }
    } else {
      await new Promise(resolve => setTimeout(resolve, 400));
      const lat = Math.floor(Math.random() * 180) + 20;
      node.latency = `${lat} ms`;
    }
  } catch (e: any) {
    node.latency = 'timeout';
  } finally {
    node.testing = false;
  }
};

/**
 * 整组测速：并发（每批 5 个）测当前组所有节点；非活动组临时拉起离线实例统一测。
 * @param silent  true 时不弹「开始测速」提示（下拉刷新触发时用）
 */
const testAllLatency = async (silent: boolean = false) => {
  if (!activeGroup.value || activeGroup.value.configs.length === 0) return;
  if (!silent) {
    showToast(t('nodes.startTestGroup'));
  }

  // 先全部置为测速中
  activeGroup.value.configs.forEach(filename => {
    const fullPath = `${selectedGroupDirName.value}/${filename}`;
    if (allNodes.value[fullPath]) {
      allNodes.value[fullPath].testing = true;
      allNodes.value[fullPath].latency = 'testing...';
    }
  });

  try {
    if (isKsu) {
      const isRunning = await checkMainServiceRunning();
      const activeGroupDirName = currentConfigPath.value ? currentConfigPath.value.split('/')[0] : '';
      const isActiveGroup = isRunning && activeGroupDirName && selectedGroupDirName.value === activeGroupDirName;

      let host = apiHost.value;
      let secret = apiSecret.value;
      let pid = 0;

      if (!isActiveGroup) {
        pid = await startOfflineTestProcess(selectedGroupDirName.value, activeGroup.value.configs);
        host = '127.0.0.1:19999';
        secret = 'latency_test';
      }

      try {
        // 并发测速（每批限 5 个，避免压垮 WebView 或网络）
        const configs = [...activeGroup.value.configs];
        const batchSize = 5;
        for (let i = 0; i < configs.length; i += batchSize) {
          const batch = configs.slice(i, i + batchSize);
          await Promise.all(batch.map(async (filename) => {
            const fullPath = `${selectedGroupDirName.value}/${filename}`;
            const node = allNodes.value[fullPath];
            if (!node) return;
            try {
              const encodedTag = encodeURIComponent(node.tag);
              const encodedUrl = encodeURIComponent('https://www.gstatic.com/generate_204');
              const url = `http://${host}/proxies/${encodedTag}/delay?timeout=5000&url=${encodedUrl}`;
              
              const controller = new AbortController();
              const timer = setTimeout(() => controller.abort(), 6000);
              const res = await fetch(url, {
                headers: { 'Authorization': `Bearer ${secret}` },
                signal: controller.signal
              });
              clearTimeout(timer);
              
              if (res.ok) {
                const data = await res.json();
                if (data.delay !== undefined && data.delay >= 0) {
                  node.latency = `${data.delay} ms`;
                } else {
                  node.latency = 'failed';
                }
              } else {
                node.latency = 'failed';
              }
            } catch {
              node.latency = 'timeout';
            } finally {
              node.testing = false;
            }
          }));
          // 批次之间略作错峰
          await new Promise(resolve => setTimeout(resolve, 100));
        }
      } finally {
        if (pid > 0) {
          await stopOfflineTestProcess(pid);
        }
      }
    } else {
      // mock：并行模拟测速
      activeGroup.value.configs.forEach((filename, i) => {
        setTimeout(async () => {
          const fullPath = `${selectedGroupDirName.value}/${filename}`;
          if (allNodes.value[fullPath]) {
            const lat = Math.floor(Math.random() * 180) + 20;
            allNodes.value[fullPath].latency = `${lat} ms`;
            allNodes.value[fullPath].testing = false;
          }
        }, i * 80);
      });
    }
  } catch (err: any) {
    showToast(t('nodes.testGroupFailed', { msg: err.message || err }));
    activeGroup.value.configs.forEach(filename => {
      const fullPath = `${selectedGroupDirName.value}/${filename}`;
      if (allNodes.value[fullPath]) {
        allNodes.value[fullPath].testing = false;
        allNodes.value[fullPath].latency = 'failed';
      }
    });
  }
};

// ===================================================================
// 顶栏暴露的方法 / 导入 / 订阅与分组管理
// ===================================================================

/** 打开显示设置弹窗（供顶栏齿轮按钮调用）。 */
const openDisplaySettings = () => {
  showDisplaySettingsDialog.value = true;
};

/** 打开节点菜单（供顶栏三点按钮调用）。 */
const openNodesMenu = () => {
  showMenu.value = true;
};

/** 关闭节点菜单。 */
const closeMenu = () => {
  showMenu.value = false;
};

/** 触发隐藏的文件选择框（导入节点 JSON 文件）。 */
const triggerImportFile = () => {
  showMenu.value = false;
  fileInputRef.value?.click();
};

/** 读取选中文件文本并交给 importNodeFromText 处理。 */
const handleFileChange = (e: Event) => {
  const target = e.target as HTMLInputElement;
  if (target.files && target.files.length > 0) {
    const file = target.files[0];
    const reader = new FileReader();
    reader.onload = (event) => {
      const content = event.target?.result as string;
      if (content && content.trim()) {
        importNodeFromText(content, file.name);
      }
    };
    reader.readAsText(file);
    target.value = '';
  }
};

/**
 * 导入节点：真机经 subscription.sh stdin 落地（base64 规避转义），mock 直接解析入内存；
 * 若内容是订阅链接则改为打开「添加订阅」弹窗。
 * @param content        节点 JSON 文本或订阅链接
 * @param filenameLabel  文件名标签（用于默认命名）
 */
const importNodeFromText = async (content: string, filenameLabel: string = 'import.json') => {
  try {
    if (isKsu) {
      const utf8Bytes = new TextEncoder().encode(content);
      let binary = '';
      const len = utf8Bytes.byteLength;
      for (let i = 0; i < len; i++) {
        binary += String.fromCharCode(utf8Bytes[i]);
      }
      const base64Content = btoa(binary);

      const targetDir = selectedGroupDirName.value || 'default';
      const targetPath = `/data/adb/modules/netproxy/config/singbox/outbounds/${targetDir}`;
      const cmd = `echo '${base64Content}' | base64 -d | sh '/data/adb/modules/netproxy/scripts/core/subscription.sh' stdin '${targetPath}'`;

      const res = await execAsync(cmd);
      if (res.errno !== 0) {
        throw new Error(res.stderr || 'Import failed');
      }
      await loadNodes();
      showToast(t('nodes.importSuccess'));
    } else {
      const parsed = JSON.parse(content);
      const tag = parsed.tag || parsed.name || filenameLabel.replace('.json', '');
      const protocol = (parsed.type || parsed.protocol || 'VMESS').toUpperCase();
      
      const newFilename = `imported_${Date.now().toString().slice(-4)}_${filenameLabel}`;
      const group = selectedGroupDirName.value;
      const fullPath = `${group}/${newFilename}`;

      allNodes.value[fullPath] = {
        tag: tag,
        protocol: protocol,
        latency: '',
        testing: false
      };
      
      if (activeGroup.value) {
        activeGroup.value.configs.push(newFilename);
      }
      showToast(t('nodes.importedNodeConfig', { tag }));
    }
  } catch (err) {
    if (content.startsWith('http://') || content.startsWith('https://')) {
      subUrl.value = content.trim();
      subName.value = filenameLabel.replace('.txt', '').replace('.json', '') || t('nodes.defaultSubName');
      showAddSubDialog.value = true;
      showToast(t('nodes.subLinkDetected'));
    } else {
      showToast(t('nodes.importFailed'));
    }
  }
};

/** 从剪贴板读取并导入节点。 */
const triggerImportClipboard = async () => {
  showMenu.value = false;
  try {
    const content = await navigator.clipboard.readText();
    if (content && content.trim()) {
      await importNodeFromText(content, 'clipboard.json');
    } else {
      showToast(t('nodes.clipboardEmpty'));
    }
  } catch (err) {
    showToast(t('nodes.clipboardFailed'));
  }
};

/** 打开「添加订阅」弹窗。 */
const triggerAddSubDialog = () => {
  showMenu.value = false;
  showAddSubDialog.value = true;
};

/** 提交添加订阅：真机经 subscription.sh add 拉取并落地，mock 造两个节点。 */
const handleAddSubscriptionSubmit = async () => {
  if (!subName.value.trim() || !subUrl.value.trim()) {
    showToast(t('nodes.nameUrlRequired'));
    return;
  }

  const name = subName.value.trim();
  const url = subUrl.value.trim();
  const ua = subUa.value.trim();
  const hwid = subHwid.value.trim();

  showToast(t('nodes.importingSub', { name }));
  try {
    if (isKsu) {
      let subCmd = `sh /data/adb/modules/netproxy/scripts/core/subscription.sh add "${name}" "${url}"`;
      if (ua) subCmd += ` -ua "${ua}"`;
      if (hwid) subCmd += ` -hwid "${hwid}"`;
      const res = await execAsync(subCmd);
      if (res.errno !== 0) {
        throw new Error(res.stderr || 'Failed to add subscription');
      }
      await loadNodes();
    } else {
      const dir = `sub_${Date.now()}`;
      configGroups.value.push({
        name: name,
        dirName: dir,
        type: 'subscription',
        configs: ['node_1.json', 'node_2.json']
      });
      allNodes.value[`${dir}/node_1.json`] = { tag: `${name} - 节点 01`, protocol: 'VMESS', latency: '', testing: false };
      allNodes.value[`${dir}/node_2.json`] = { tag: `${name} - 节点 02`, protocol: 'TROJAN', latency: '', testing: false };
    }
    showToast(t('nodes.subImported', { name }));
    subName.value = '';
    subUrl.value = '';
    subUa.value = '';
    subHwid.value = '';
    showAddSubDialog.value = false;
  } catch (err: any) {
    showToast(t('nodes.subImportFailed', { msg: err.message || err }));
  }
};

/** 打开「新建分组」弹窗。 */
const triggerCreateGroupDialog = () => {
  showMenu.value = false;
  showCreateGroupDialog.value = true;
};

/** 提交新建自定义分组（真机 mkdir 对应目录）。 */
const handleCreateGroupSubmit = async () => {
  if (!newGroupName.value.trim()) return;
  const name = newGroupName.value.trim();
  showToast(t('nodes.creatingGroup', { name }));
  try {
    if (isKsu) {
      await execAsync(`mkdir -p "/data/adb/modules/netproxy/config/singbox/outbounds/${name}"`);
      await loadNodes();
    } else {
      const dir = name;
      configGroups.value.push({
        name: name,
        dirName: dir,
        type: 'custom',
        configs: []
      });
    }
    showToast(t('nodes.groupCreated', { name }));
    newGroupName.value = '';
    showCreateGroupDialog.value = false;
  } catch (err: any) {
    showToast(t('nodes.groupCreateFailed', { msg: err.message || err }));
  }
};

/** 更新当前订阅分组（真机经 subscription.sh update）。 */
const triggerUpdateSubscription = async () => {
  showMenu.value = false;
  if (!activeGroup.value || activeGroup.value.type !== 'subscription') return;
  showToast(t('nodes.updatingSub', { name: activeGroup.value.name }));
  try {
    if (isKsu) {
      const cmd = `sh /data/adb/modules/netproxy/scripts/core/subscription.sh update "${activeGroup.value.name}"`;
      const res = await execAsync(cmd);
      if (res.errno !== 0) {
        throw new Error(res.stderr || 'Failed to update subscription');
      }
      await loadNodes();
    } else {
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    showToast(t('nodes.subUpdated', { name: activeGroup.value?.name }));
  } catch (err: any) {
    showToast(t('nodes.subUpdateFailed', { msg: err.message || err }));
  }
};

/** 删除当前订阅分组（需确认；真机经 subscription.sh remove）。 */
const triggerDeleteSubscription = async () => {
  showMenu.value = false;
  if (!activeGroup.value || activeGroup.value.type !== 'subscription') return;
  
  if (!confirm(t('nodes.confirmDeleteSub', { name: activeGroup.value.name }))) return;

  const toRemoveName = activeGroup.value.name;
  const toRemoveDir = activeGroup.value.dirName;

  showToast(t('nodes.deletingSub', { name: toRemoveName }));
  try {
    if (isKsu) {
      const cmd = `sh /data/adb/modules/netproxy/scripts/core/subscription.sh remove "${toRemoveName}"`;
      const res = await execAsync(cmd);
      if (res.errno !== 0) {
        throw new Error(res.stderr || 'Failed to delete subscription');
      }
      await loadNodes();
    } else {
      configGroups.value = configGroups.value.filter(g => g.dirName !== toRemoveDir);
    }
    selectedGroupDirName.value = configGroups.value[0]?.dirName || '';
    showToast(t('nodes.subDeleted'));
  } catch (err: any) {
    showToast(t('nodes.subDeleteFailed', { msg: err.message || err }));
  }
};

/** 删除当前自定义分组（需确认；真机 rm -rf 对应目录）。 */
const triggerDeleteCustomGroup = async () => {
  showMenu.value = false;
  if (!activeGroup.value || activeGroup.value.type !== 'custom') return;

  if (!confirm(t('nodes.confirmDeleteGroup', { name: activeGroup.value.name }))) return;

  const toRemoveDir = activeGroup.value.dirName;
  showToast(t('nodes.deletingGroup', { name: activeGroup.value.name }));
  try {
    if (isKsu) {
      await execAsync(`rm -rf "/data/adb/modules/netproxy/config/singbox/outbounds/${toRemoveDir}"`);
      await loadNodes();
    } else {
      configGroups.value = configGroups.value.filter(g => g.dirName !== toRemoveDir);
    }
    selectedGroupDirName.value = configGroups.value[0]?.dirName || '';
    showToast(t('nodes.groupDeleted'));
  } catch (err: any) {
    showToast(t('nodes.groupDeleteFailed', { msg: err.message || err }));
  }
};

/** 清理当前组中 timeout/failed 的失效节点（需确认；真机逐个 rm）。 */
const triggerCleanInvalidNodes = async () => {
  showMenu.value = false;
  if (!activeGroup.value) return;

  const toDelete: string[] = [];
  activeGroup.value.configs.forEach(filename => {
    const fullPath = `${selectedGroupDirName.value}/${filename}`;
    const node = allNodes.value[fullPath];
    if (node && (node.latency === 'timeout' || node.latency === 'failed')) {
      toDelete.push(filename);
    }
  });

  if (toDelete.length === 0) {
    showToast(t('nodes.noInvalidNodes'));
    return;
  }

  if (!confirm(t('nodes.confirmCleanInvalid', { count: toDelete.length }))) return;

  showToast(t('nodes.cleaningInvalid', { count: toDelete.length }));
  try {
    if (isKsu) {
      for (const filename of toDelete) {
        const fullPath = `${selectedGroupDirName.value}/${filename}`;
        const path = `/data/adb/modules/netproxy/config/singbox/outbounds/${fullPath}`;
        await execAsync(`rm -f "${path}"`);
      }
      await loadNodes();
    } else {
      activeGroup.value.configs = activeGroup.value.configs.filter(c => !toDelete.includes(c));
      toDelete.forEach(filename => {
        const fullPath = `${selectedGroupDirName.value}/${filename}`;
        delete allNodes.value[fullPath];
      });
    }
    showToast(t('nodes.cleanInvalidDone'));
  } catch (err: any) {
    showToast(t('nodes.cleanInvalidFailed', { msg: err.message || err }));
  }
};

// ===================================================================
// 节点操作弹窗：编辑 / 保存 / 导出 / 删除
// ===================================================================

/** 打开节点 JSON 编辑弹窗（真机读取文件内容，mock 给示例）。 */
const handleEditNodeClick = async () => {
  showNodeActionDialog.value = false;
  if (!selectedActionNode.value) return;
  
  const fullPath = `${selectedGroupDirName.value}/${selectedActionNode.value}`;
  const node = allNodes.value[fullPath];
  if (!node) return;

  try {
    if (isKsu) {
      const path = `/data/adb/modules/netproxy/config/singbox/outbounds/${fullPath}`;
      editingContent.value = await readFileContent(path);
    } else {
      editingContent.value = JSON.stringify({
        tag: node.tag,
        protocol: node.protocol,
        server: '104.21.75.132',
        port: 443,
        uuid: 'a89c3b28-1bda-4fde-98aa-e91bcf80b2e8',
        transport: {
          type: 'ws',
          path: '/graphql'
        }
      }, null, 2);
    }
    showEditDialog.value = true;
  } catch (err: any) {
    showToast(t('nodes.readNodeFailed', { msg: err.message || err }));
  }
};

/** 保存编辑的节点 JSON（先校验合法 JSON，真机写文件并重载）。 */
const handleSaveNodeEdit = async () => {
  if (!selectedActionNode.value) return;
  const fullPath = `${selectedGroupDirName.value}/${selectedActionNode.value}`;
  try {
    JSON.parse(editingContent.value); // 校验是否为合法 JSON
    if (isKsu) {
      const path = `/data/adb/modules/netproxy/config/singbox/outbounds/${fullPath}`;
      await writeFileContent(path, editingContent.value);
      await loadNodes();
    } else {
      const parsed = JSON.parse(editingContent.value);
      if (parsed.tag) allNodes.value[fullPath].tag = parsed.tag;
      if (parsed.protocol) allNodes.value[fullPath].protocol = parsed.protocol.toUpperCase();
    }
    showToast(t('nodes.nodeSaved'));
    showEditDialog.value = false;
  } catch (err: any) {
    showToast(t('nodes.saveFailed', { msg: err.message || err }));
  }
};

/** 导出节点为分享链接并复制到剪贴板（真机经 subscription.sh convert）。 */
const handleExportNodeClick = async () => {
  showNodeActionDialog.value = false;
  if (!selectedActionNode.value) return;
  const fullPath = `${selectedGroupDirName.value}/${selectedActionNode.value}`;
  const node = allNodes.value[fullPath];
  if (!node) return;

  try {
    let link = '';
    if (isKsu) {
      const path = `/data/adb/modules/netproxy/config/singbox/outbounds/${fullPath}`;
      const cmd = `sh /data/adb/modules/netproxy/scripts/core/subscription.sh convert "${path}"`;
      const res = await execAsync(cmd);
      if (res.errno !== 0 || !res.stdout.trim()) {
        throw new Error(res.stderr || 'Failed to export node link');
      }
      link = res.stdout.trim();
    } else {
      link = `${node.protocol.toLowerCase()}://graphql@104.21.75.132:443?type=ws&path=/graphql#${encodeURIComponent(node.tag)}`;
    }
    
    await navigator.clipboard.writeText(link);
    showToast(t('nodes.nodeLinkCopied'));
  } catch (err: any) {
    showToast(t('nodes.exportFailed', { msg: err.message || err }));
  }
};

/** 删除节点（当前使用中的不可删；需确认；真机 rm 后重载）。 */
const handleDeleteNodeClick = async () => {
  showNodeActionDialog.value = false;
  if (!selectedActionNode.value) return;
  
  const filename = selectedActionNode.value;
  const fullPath = `${selectedGroupDirName.value}/${filename}`;
  if (currentConfigPath.value === fullPath) {
    showToast(t('nodes.cannotDeleteCurrent'));
    return;
  }

  if (!confirm(t('nodes.confirmDeleteNode', { tag: allNodes.value[fullPath]?.tag }))) return;

  try {
    if (isKsu) {
      const path = `/data/adb/modules/netproxy/config/singbox/outbounds/${fullPath}`;
      await execAsync(`rm -f "${path}"`);
      await loadNodes();
    } else {
      delete allNodes.value[fullPath];
      if (activeGroup.value) {
        activeGroup.value.configs = activeGroup.value.configs.filter(c => c !== filename);
      }
    }
    showToast(t('nodes.nodeDeleted'));
  } catch (err: any) {
    showToast(t('nodes.nodeDeleteFailed', { msg: err.message || err }));
  }
};

// ===== 虚拟滚动引擎 (复用父级 .page-scroller 作为滚动源) =====
const listEl = ref<HTMLElement | null>(null);   // .nodes-virtual 容器
let scrollerEl: HTMLElement | null = null;       // 父级 .page-scroller
const scrollTop = ref(0);
const viewportH = ref(0);
const listTop = ref(0);                          // 列表相对滚动内容顶部的偏移
const measuredRowH = ref(0);                     // 实测行高 (含间距)
const VS_OVERSCAN = 4;                           // 上下额外渲染的行数

// 各尺寸的卡片估算高度 (含 10px gap)，实测后用 measuredRowH 校准
const estimatedRowH = computed(() => {
  const base = nodeItemSize.value === 'minimal' ? 52 : nodeItemSize.value === 'compact' ? 60 : 72;
  return base + 10;
});
const rowHeight = computed(() => measuredRowH.value || estimatedRowH.value);

// 列数：固定映射，与 CSS grid-template-columns 及 Android 一致（宽松1/标准2/紧凑3）
const columns = computed(() => {
  const d = nodeLayoutDensity.value;
  if (d === 'loose') return 1;
  if (d === 'standard') return 2;
  return 3; // compact
});

const totalRows = computed(() => Math.ceil(viewNodes.value.length / columns.value));
const totalHeight = computed(() => totalRows.value * rowHeight.value);

// 可见行区间 [startRow, endRow)
const visibleRange = computed(() => {
  const rh = rowHeight.value;
  if (rh <= 0 || viewNodes.value.length === 0) return { start: 0, end: 0, offsetY: 0 };
  const relTop = scrollTop.value - listTop.value;
  let startRow = Math.floor(relTop / rh) - VS_OVERSCAN;
  if (startRow < 0) startRow = 0;
  const visibleRows = Math.ceil(viewportH.value / rh) + VS_OVERSCAN * 2;
  let endRow = startRow + visibleRows;
  if (endRow > totalRows.value) endRow = totalRows.value;
  return { start: startRow, end: endRow, offsetY: startRow * rh };
});

// 当前应渲染的可见节点切片
const visibleNodes = computed(() => {
  const cols = columns.value;
  const { start, end } = visibleRange.value;
  return viewNodes.value.slice(start * cols, end * cols);
});

// ===== 列表模式：扁平渲染项 + 虚拟滚动 =====
const HEADER_H = 64;  // 分组标题卡估算高度（含间距）

/** 列表模式的扁平渲染项：分组标题(header) 或 一行节点(row)，含距列表顶的偏移与高度。 */
interface FlatItem {
  type: 'header' | 'row';
  top: number;            // 距列表顶的偏移
  height: number;
  groupName: string;
  dirName: string;
  count?: number;         // header：节点数
  expanded?: boolean;     // header：是否展开
  nodes?: ViewNode[];     // row：该行的节点（1~列数 个）
}

// 把所有分组展开成扁平项（header + 展开组的节点行），并算好各项偏移
const flatItems = computed<FlatItem[]>(() => {
  const cols = columns.value;
  const rh = rowHeight.value;
  const items: FlatItem[] = [];
  let top = 0;
  for (const group of configGroups.value) {
    const expanded = expandedGroups.value.has(group.dirName);
    items.push({
      type: 'header', top, height: HEADER_H,
      groupName: group.name, dirName: group.dirName,
      count: group.configs.length, expanded
    });
    top += HEADER_H;
    if (expanded) {
      const nodes = buildGroupViewNodes(group.dirName, group.configs);
      for (let i = 0; i < nodes.length; i += cols) {
        items.push({
          type: 'row', top, height: rh,
          groupName: group.name, dirName: group.dirName,
          nodes: nodes.slice(i, i + cols)
        });
        top += rh;
      }
    }
  }
  return items;
});

const listTotalHeight = computed(() =>
  flatItems.value.length ? flatItems.value[flatItems.value.length - 1].top + flatItems.value[flatItems.value.length - 1].height : 0
);

// 列表模式可见项窗口（按偏移裁剪 + overscan）
const listVisible = computed(() => {
  const items = flatItems.value;
  if (items.length === 0) return { items: [] as FlatItem[], offsetY: 0 };
  const relTop = scrollTop.value - listTop.value;
  const top = relTop - HEADER_H * VS_OVERSCAN;
  const bottom = relTop + viewportH.value + HEADER_H * VS_OVERSCAN;
  let startIdx = 0;
  let endIdx = items.length;
  for (let i = 0; i < items.length; i++) {
    if (items[i].top + items[i].height >= top) { startIdx = i; break; }
  }
  for (let i = startIdx; i < items.length; i++) {
    if (items[i].top > bottom) { endIdx = i; break; }
  }
  return { items: items.slice(startIdx, endIdx), offsetY: items[startIdx].top };
});

// 读取滚动状态 (rAF 节流)
let vsRaf = 0;
const onScroll = () => {
  if (vsRaf) return;
  vsRaf = requestAnimationFrame(() => {
    vsRaf = 0;
    if (!scrollerEl) return;
    scrollTop.value = scrollerEl.scrollTop;
    viewportH.value = scrollerEl.clientHeight;
    if (listEl.value) {
      // 列表顶相对滚动内容顶 = 列表 offsetTop 距 scroller 内容
      const lr = listEl.value.getBoundingClientRect();
      const sr = scrollerEl.getBoundingClientRect();
      listTop.value = (lr.top - sr.top) + scrollerEl.scrollTop;
    }
  });
};

// 实测一行真实高度，校准估算值
const measureRow = () => {
  if (!listEl.value) return;
  const card = listEl.value.querySelector('.node-item-card') as HTMLElement | null;
  if (card) {
    const h = card.offsetHeight + 10; // + 行间距
    if (h > 0 && Math.abs(h - measuredRowH.value) > 1) measuredRowH.value = h;
  }
};

let vsResizeObserver: ResizeObserver | null = null;
const attachScroll = () => {
  scrollerEl = document.querySelector('.page-scroller');
  if (scrollerEl) {
    scrollerEl.addEventListener('scroll', onScroll, { passive: true });
    viewportH.value = scrollerEl.clientHeight;
    scrollTop.value = scrollerEl.scrollTop;
  }
  if (typeof ResizeObserver !== 'undefined') {
    vsResizeObserver = new ResizeObserver(() => { onScroll(); measureRow(); });
    if (scrollerEl) vsResizeObserver.observe(scrollerEl);
  }
  // 初次定位与实测
  nextTick(() => { onScroll(); measureRow(); });
};
const detachScroll = () => {
  if (scrollerEl) scrollerEl.removeEventListener('scroll', onScroll);
  if (vsResizeObserver) { vsResizeObserver.disconnect(); vsResizeObserver = null; }
  if (vsRaf) { cancelAnimationFrame(vsRaf); vsRaf = 0; }
};

// 数据/密度/尺寸变化后重新定位与实测
watch([viewNodes, nodeLayoutDensity, nodeItemSize, selectedGroupDirName, nodeLayoutStyle, flatItems], () => {
  nextTick(() => { onScroll(); measureRow(); });
});

onActivated(attachScroll);
onDeactivated(detachScroll);
onUnmounted(detachScroll);

onMounted(async () => {
  isLoading.value = true;
  await loadApiConfig();
  await loadNodes();
});

defineExpose({
  openDisplaySettings,
  openNodesMenu
});
</script>

<template>
  <div 
    class="nodes-container animated-fade-in"
    @touchstart="handleTouchStart"
    @touchmove="handleTouchMove"
    @touchend="handleTouchEnd"
  >
    
    <!-- 下拉刷新指示器 -->
    <div 
      class="pull-to-refresh-indicator" 
      v-show="pullDelta > 0 || isRefreshing"
      :style="{ height: pullDelta + 'px', opacity: pullDelta > 0 || isRefreshing ? 1 : 0 }"
      :class="{ 'refreshing': isRefreshing }"
    >
      <div class="refresh-spinner" v-if="isRefreshing">
        <svg class="spinner-svg" viewBox="0 0 24 24">
          <circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="3"></circle>
        </svg>
      </div>
      <div class="refresh-arrow" v-else :style="{ transform: `rotate(${Math.min(pullDelta * 3.6, 180)}deg)` }">↓</div>
      <span class="refresh-label">{{ refreshText }}</span>
    </div>



    <!-- 分组标签栏（仅标签页模式） -->
    <div class="groups-tab-bar" v-if="nodeLayoutStyle === 'tab' && configGroups.length > 0">
      <button
        v-for="group in configGroups"
        :key="group.dirName"
        :class="['group-tab-item', selectedGroupDirName === group.dirName ? 'active' : '']"
        @click="selectedGroupDirName = group.dirName">
        {{ group.name }} ({{ group.configs.length }})
      </button>
    </div>

    <!-- 标签栏下方的线性加载进度 -->
    <div v-if="isLoading && configGroups.length > 0" class="loading-bar-container">
      <md-linear-progress indeterminate></md-linear-progress>
    </div>

    <!-- 首次打开/尚无分组时的环形加载 -->
    <div v-if="isLoading && configGroups.length === 0" class="loading-state">
      <md-circular-progress indeterminate></md-circular-progress>
    </div>

    <!-- ============ 标签页模式：当前组虚拟网格 ============ -->
    <template v-else-if="nodeLayoutStyle === 'tab'">
      <!-- 空状态 -->
      <div v-if="viewNodes.length === 0" class="empty-state">
        <md-icon class="empty-icon">
          <svg viewBox="0 0 24 24">
            <path d="M19 13H5c-1.1 0-2 .9-2 2v4c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2v-4c0-1.1-.9-2-2-2zM19 3H5c-1.1 0-2 .9-2 2v4c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM9 18H7v-2h2v2zm0-10H7V6h2v2z" />
          </svg>
        </md-icon>
        <span class="empty-text">{{ t('nodes.emptyGroup') }}</span>
      </div>

      <!-- 虚拟滚动：外层撑出总高度，内层 grid 只渲染可见切片并按行偏移定位 -->
      <div v-else ref="listEl" class="nodes-virtual" :style="{ height: totalHeight + 'px' }">
        <div
          :class="['nodes-grid', `density-${nodeLayoutDensity}`]"
          :style="{ transform: `translateY(${visibleRange.offsetY}px)` }">
          <div
            v-for="node in visibleNodes"
            :key="node.key"
            :class="[
              'node-item-card',
              `size-${nodeItemSize}`,
              node.isCurrent ? 'selected' : ''
            ]"
            @click="handleSelectNode(node.filename)"
            @touchstart="startPress(node.filename)"
            @touchend="endPress"
            @touchmove="endPress"
            @mousedown="startPress(node.filename)"
            @mouseup="endPress"
            @mouseleave="endPress"
            @contextmenu.prevent
          >
            <md-ripple></md-ripple>
            <span class="node-tag">{{ node.tag }}</span>
            <div class="node-sub-row">
              <span class="node-protocol">{{ node.protocol }}</span>
              <span
                v-if="node.hasLatency"
                class="node-latency"
                :style="{ color: node.latencyColor }"
                @click.stop="testNodeLatency(node.filename)">
                {{ node.latencyText }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </template>

    <!-- ============ 列表模式：分组纵向可折叠 + 扁平虚拟滚动 ============ -->
    <template v-else>
      <div v-if="configGroups.length === 0" class="empty-state">
        <span class="empty-text">{{ t('nodes.emptyGroups') }}</span>
      </div>
      <div v-else ref="listEl" class="nodes-virtual" :style="{ height: listTotalHeight + 'px' }">
        <div class="nodes-list-inner" :style="{ transform: `translateY(${listVisible.offsetY}px)` }">
          <template v-for="(item, idx) in listVisible.items" :key="item.type + item.dirName + idx">
            <!-- 分组标题卡 -->
            <div
              v-if="item.type === 'header'"
              class="group-header-card"
              @click="toggleGroup(item.dirName)">
              <md-ripple></md-ripple>
              <div class="group-header-text">
                <span class="group-header-name">{{ item.groupName }}</span>
                <span class="group-header-count">{{ t('nodes.nodeCount', { count: item.count }) }}</span>
              </div>
              <md-icon class="group-header-arrow">
                <svg viewBox="0 0 24 24">
                  <path :d="item.expanded ? 'M7.41 15.41L12 10.83l4.59 4.58L18 14l-6-6-6 6z' : 'M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6z'" />
                </svg>
              </md-icon>
            </div>

            <!-- 节点行（密度列数） -->
            <div
              v-else
              :class="['nodes-grid', `density-${nodeLayoutDensity}`, 'nodes-list-row']">
              <div
                v-for="node in item.nodes"
                :key="node.key"
                :class="[
                  'node-item-card',
                  `size-${nodeItemSize}`,
                  node.isCurrent ? 'selected' : ''
                ]"
                @click="onListSelect(item.dirName, node.filename)"
                @touchstart="onListPressStart(item.dirName, node.filename)"
                @touchend="endPress"
                @touchmove="endPress"
                @mousedown="onListPressStart(item.dirName, node.filename)"
                @mouseup="endPress"
                @mouseleave="endPress"
                @contextmenu.prevent
              >
                <md-ripple></md-ripple>
                <span class="node-tag">{{ node.tag }}</span>
                <div class="node-sub-row">
                  <span class="node-protocol">{{ node.protocol }}</span>
                  <span
                    v-if="node.hasLatency"
                    class="node-latency"
                    :style="{ color: node.latencyColor }"
                    @click.stop="onListLatency(item.dirName, node.filename)">
                    {{ node.latencyText }}
                  </span>
                </div>
              </div>
            </div>
          </template>
        </div>
      </div>
    </template>

    <!-- 文件导入用的隐藏 input -->
    <input 
      type="file" 
      ref="fileInputRef" 
      style="display: none" 
      accept=".json,text/*" 
      @change="handleFileChange" 
    />

    <!-- 顶栏下拉菜单容器 -->
    <teleport to="body">
      <div class="menu-scrim" v-if="showMenu" @click="closeMenu"></div>
      <div class="nodes-menu-popup" v-if="showMenu">
        <div class="menu-item-nested">
          <span class="menu-label-header">{{ t('nodes.menuAddNode') }}</span>
          <button class="sub-menu-item" @click="triggerImportClipboard">
            <md-ripple></md-ripple>
            {{ t('nodes.importClipboard') }}
          </button>
          <button class="sub-menu-item" @click="triggerImportFile">
            <md-ripple></md-ripple>
            {{ t('nodes.importFile') }}
          </button>
          <button class="sub-menu-item" @click="triggerAddSubDialog">
            <md-ripple></md-ripple>
            {{ t('nodes.importLink') }}
          </button>
        </div>
        <div class="menu-divider"></div>
        <button class="menu-item-row" @click="testAllLatency(false)">
          <md-ripple></md-ripple>
          {{ t('nodes.latencyTest') }}
        </button>
        <div class="menu-divider"></div>
        <div class="menu-item-nested">
          <span class="menu-label-header">{{ t('nodes.manage') }}</span>
          <button class="sub-menu-item" @click="triggerCreateGroupDialog">
            <md-ripple></md-ripple>
            {{ t('nodes.createGroup') }}
          </button>
          <button v-if="activeGroup?.type === 'subscription'" class="sub-menu-item" @click="triggerUpdateSubscription">
            <md-ripple></md-ripple>
            {{ t('nodes.updateSub') }}
          </button>
          <button v-if="activeGroup?.type === 'subscription'" class="sub-menu-item delete-text" @click="triggerDeleteSubscription">
            <md-ripple></md-ripple>
            {{ t('nodes.deleteSub') }}
          </button>
          <button v-if="activeGroup?.type === 'custom'" class="sub-menu-item delete-text" @click="triggerDeleteCustomGroup">
            <md-ripple></md-ripple>
            {{ t('nodes.deleteGroup') }}
          </button>
          <button class="sub-menu-item" @click="triggerCleanInvalidNodes">
            <md-ripple></md-ripple>
            {{ t('nodes.cleanInvalid') }}
          </button>
        </div>
      </div>
    </teleport>

    <!-- 弹窗容器（不占布局空间、不拦截触摸） -->
    <div class="dialogs-wrapper">
      <!-- 节点显示设置弹窗 -->
      <md-dialog :open="showDisplaySettingsDialog" @close="showDisplaySettingsDialog = false" class="transparent-scrim">
        <div slot="headline">{{ t('nodes.settingsTitle') }}</div>
        <div slot="content" class="display-dialog-content">

          <div class="preference-group-card">
            <!-- 布局样式选择 -->
            <div class="dropdown-pref-row">
              <div class="dropdown-text">
                <span class="dropdown-title">{{ t('nodes.layoutStyle') }}</span>
              </div>
              <select v-model="nodeLayoutStyle" class="pref-selector">
                <option value="tab">{{ t('nodes.layoutTab') }}</option>
                <option value="list">{{ t('nodes.layoutList') }}</option>
              </select>
            </div>

            <div class="pref-inner-divider"></div>

            <!-- 排序方式选择 -->
            <div class="dropdown-pref-row">
              <div class="dropdown-text">
                <span class="dropdown-title">{{ t('nodes.sort') }}</span>
              </div>
              <select v-model="nodeSortType" class="pref-selector">
                <option value="default">{{ t('nodes.sortDefault') }}</option>
                <option value="latency">{{ t('nodes.sortLatency') }}</option>
                <option value="name">{{ t('nodes.sortName') }}</option>
              </select>
            </div>

            <div class="pref-inner-divider"></div>

            <!-- 密度（列数）选择 -->
            <div class="dropdown-pref-row">
              <div class="dropdown-text">
                <span class="dropdown-title">{{ t('nodes.density') }}</span>
              </div>
              <select v-model="nodeLayoutDensity" class="pref-selector">
                <option value="loose">{{ t('nodes.densityLoose') }}</option>
                <option value="standard">{{ t('nodes.densityStandard') }}</option>
                <option value="compact">{{ t('nodes.densityCompact') }}</option>
              </select>
            </div>

            <div class="pref-inner-divider"></div>

            <!-- 卡片尺寸选择 -->
            <div class="dropdown-pref-row">
              <div class="dropdown-text">
                <span class="dropdown-title">{{ t('nodes.size') }}</span>
              </div>
              <select v-model="nodeItemSize" class="pref-selector">
                <option value="standard">{{ t('nodes.sizeStandard') }}</option>
                <option value="compact">{{ t('nodes.sizeCompact') }}</option>
                <option value="minimal">{{ t('nodes.sizeMinimal') }}</option>
              </select>
            </div>
          </div>

        </div>
        <div slot="actions">
          <md-text-button @click="showDisplaySettingsDialog = false">{{ t('common.done') }}</md-text-button>
        </div>
      </md-dialog>

      <!-- 添加订阅弹窗 -->
      <md-dialog :open="showAddSubDialog" @close="showAddSubDialog = false">
        <div slot="headline">{{ t('nodes.addSubTitle') }}</div>
        <div slot="content" class="form-dialog-content">
          <md-outlined-text-field :label="t('nodes.subName')" v-model="subName" :placeholder="t('nodes.subNamePlaceholder')" class="form-field"></md-outlined-text-field>
          <md-outlined-text-field :label="t('nodes.subUrl')" v-model="subUrl" placeholder="https://..." class="form-field"></md-outlined-text-field>
          <md-outlined-text-field :label="t('nodes.subUaOptional')" v-model="subUa" placeholder="sing-box" class="form-field"></md-outlined-text-field>
          <md-outlined-text-field :label="t('nodes.subHwidOptional')" v-model="subHwid" placeholder="uuid" class="form-field"></md-outlined-text-field>
        </div>
        <div slot="actions">
          <md-text-button @click="showAddSubDialog = false">{{ t('common.cancel') }}</md-text-button>
          <md-text-button @click="handleAddSubscriptionSubmit">{{ t('nodes.add') }}</md-text-button>
        </div>
      </md-dialog>

      <!-- 新建分组弹窗 -->
      <md-dialog :open="showCreateGroupDialog" @close="showCreateGroupDialog = false">
        <div slot="headline">{{ t('nodes.createGroupTitle') }}</div>
        <div slot="content" class="form-dialog-content">
          <md-outlined-text-field :label="t('nodes.groupName')" v-model="newGroupName" :placeholder="t('nodes.groupNamePlaceholder')" class="form-field"></md-outlined-text-field>
        </div>
        <div slot="actions">
          <md-text-button @click="showCreateGroupDialog = false">{{ t('common.cancel') }}</md-text-button>
          <md-text-button @click="handleCreateGroupSubmit">{{ t('nodes.create') }}</md-text-button>
        </div>
      </md-dialog>

      <!-- 节点操作菜单弹窗 -->
      <md-dialog :open="showNodeActionDialog" @close="showNodeActionDialog = false" class="transparent-scrim">
        <div slot="headline">{{ selectedActionNode?.replace('.json', '') }}</div>
        <div slot="content" class="dialog-list-container">
          <md-list>
            <md-list-item type="button" @click="handleEditNodeClick">
              <md-icon slot="start">
                <svg viewBox="0 0 24 24"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>
              </md-icon>
              <div slot="headline">{{ t('nodes.edit') }}</div>
            </md-list-item>
            <md-list-item type="button" @click="handleExportNodeClick">
              <md-icon slot="start">
                <svg viewBox="0 0 24 24"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
              </md-icon>
              <div slot="headline">{{ t('nodes.export') }}</div>
            </md-list-item>
            <md-list-item type="button" @click="handleDeleteNodeClick" class="delete-item">
              <md-icon slot="start">
                <svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1-1H5v2h14V4z"/></svg>
              </md-icon>
              <div slot="headline">{{ t('common.delete') }}</div>
            </md-list-item>
          </md-list>
        </div>
        <div slot="actions">
          <md-text-button @click="showNodeActionDialog = false">{{ t('common.cancel') }}</md-text-button>
        </div>
      </md-dialog>

      <!-- 编辑节点文件弹窗 -->
      <md-dialog :open="showEditDialog" @close="showEditDialog = false" class="edit-dialog">
        <div slot="headline">{{ t('nodes.editNodeJson') }}</div>
        <div slot="content" class="editor-content-box">
          <textarea v-model="editingContent" class="raw-json-editor" spellcheck="false"></textarea>
        </div>
        <div slot="actions">
          <md-text-button @click="showEditDialog = false">{{ t('common.cancel') }}</md-text-button>
          <md-text-button @click="handleSaveNodeEdit">{{ t('common.save') }}</md-text-button>
        </div>
      </md-dialog>
    </div>
  </div>
</template>

<style scoped>
.loading-bar-container {
  width: 100%;
  margin-top: -8px;
  margin-bottom: 8px;
}

.loading-state {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 64px 0;
  width: 100%;
}

.nodes-container {
  display: flex;
  flex-direction: column;
  gap: 16px;
  position: relative;
}

/* 下拉刷新样式 */
.pull-to-refresh-indicator {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  overflow: hidden;
  transition: height 0.15s cubic-bezier(0.3, 1, 0.2, 1), opacity 0.15s ease;
  width: 100%;
  color: var(--md-sys-color-primary);
  font-size: 13px;
  font-weight: 500;
  user-select: none;
  pointer-events: none;
}

.refresh-arrow {
  font-size: 16px;
  font-weight: bold;
  transition: transform 0.15s ease;
}

.refresh-spinner {
  display: flex;
  align-items: center;
  justify-content: center;
}

.spinner-svg {
  width: 18px;
  height: 18px;
  animation: rotateSpinner 0.8s linear infinite;
}

.spinner-svg circle {
  stroke-dasharray: 40;
  stroke-dashoffset: 0;
  transform-origin: center;
  animation: dashSpinner 1.5s ease-in-out infinite;
  stroke: currentColor;
}

@keyframes rotateSpinner {
  100% {
    transform: rotate(360deg);
  }
}

@keyframes dashSpinner {
  0% {
    stroke-dashoffset: 40;
  }
  50% {
    stroke-dashoffset: 10;
    transform: rotate(135deg);
  }
  100% {
    stroke-dashoffset: 40;
    transform: rotate(450deg);
  }
}

/* 横向分组标签栏 */
.groups-tab-bar {
  position: sticky;
  top: -16px;
  background-color: var(--md-sys-color-background);
  z-index: 10;
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding: 16px 0 0 0;
  margin-top: -16px;
  scrollbar-width: none;
}

.groups-tab-bar::-webkit-scrollbar {
  display: none;
}

.group-tab-item {
  background: var(--md-sys-color-surface-container-low);
  border: 1px solid var(--md-sys-color-outline-variant);
  color: var(--md-sys-color-on-surface-variant);
  padding: 6px 14px;
  border-radius: var(--radius-full);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  transition: all 0.2s ease;
  flex-shrink: 0;
}

.group-tab-item:hover {
  background: rgba(128, 128, 128, 0.08);
  color: var(--md-sys-color-on-surface);
}

.group-tab-item.active {
  background: var(--md-sys-color-secondary-container);
  color: var(--md-sys-color-on-secondary-container);
  border-color: var(--md-sys-color-secondary-container);
}

/* 节点网格（按密度决定列数） */
.nodes-virtual {
  position: relative;
  width: 100%;
}

.nodes-grid {
  display: grid;
  gap: 10px;
}

.nodes-virtual > .nodes-grid {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  will-change: transform;
}

/* 列表模式：扁平虚拟容器内层 */
.nodes-virtual > .nodes-list-inner {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  will-change: transform;
}

/* 列表模式：每行节点网格（行内定高，行间距 10px 与 rowHeight 对齐） */
.nodes-list-row {
  box-sizing: border-box;
  margin-bottom: 10px;
}

/* 列表模式：分组标题卡 */
.group-header-card {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-sizing: border-box;
  height: 56px;
  margin-bottom: 8px;
  padding: 0 16px;
  border-radius: 16px;
  background-color: var(--md-sys-color-surface-container);
  border: 1px solid var(--md-sys-color-outline-variant);
  cursor: pointer;
  overflow: hidden;
}

.group-header-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.group-header-name {
  font-size: 14px;
  font-weight: 500;
  color: var(--md-sys-color-on-surface);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.group-header-count {
  font-size: 12px;
  color: var(--md-sys-color-on-surface-variant);
}

.group-header-arrow {
  flex-shrink: 0;
  color: var(--md-sys-color-on-surface-variant);
}

.group-header-arrow svg {
  width: 20px;
  height: 20px;
  fill: currentColor;
}

.nodes-grid.density-loose {
  grid-template-columns: 1fr;
}

.nodes-grid.density-standard {
  grid-template-columns: 1fr 1fr;
}

.nodes-grid.density-compact {
  grid-template-columns: 1fr 1fr 1fr;
}

/* 节点卡片（仿 Miuix 规格） */
.node-item-card {
  background-color: var(--md-sys-color-surface-container);
  border-radius: var(--radius-xl);
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  width: 100%;
  box-sizing: border-box;
  cursor: pointer;
  position: relative;
  overflow: hidden;
  border: 1.5px solid transparent;
  transition: background-color 0.2s ease;
}

.node-item-card:hover {
  background-color: var(--md-sys-color-surface-container-high);
}

/* 选中态样式 */
.node-item-card.selected {
  background-color: rgba(103, 80, 164, 0.08); /* 主色 10% 透明度 */
  border-color: var(--md-sys-color-primary);
}

/* 卡片尺寸规格 */
.node-item-card.size-standard {
  padding: 16px;
  min-height: 72px;
  border-radius: 16px;
}
.node-item-card.size-standard .node-tag {
  font-size: 14px;
}
.node-item-card.size-standard .node-protocol {
  font-size: 12px;
}
.node-item-card.size-standard .node-latency {
  font-size: 11px;
}
.node-item-card.size-standard .node-sub-row {
  margin-top: 8px;
}

.node-item-card.size-compact {
  padding: 12px;
  min-height: 60px;
  border-radius: 12px;
}
.node-item-card.size-compact .node-tag {
  font-size: 13px;
}
.node-item-card.size-compact .node-protocol {
  font-size: 11px;
}
.node-item-card.size-compact .node-latency {
  font-size: 10px;
}
.node-item-card.size-compact .node-sub-row {
  margin-top: 4px;
}

.node-item-card.size-minimal {
  padding: 8px 12px;
  min-height: 52px;
  border-radius: 8px;
}
.node-item-card.size-minimal .node-tag {
  font-size: 12px;
}
.node-item-card.size-minimal .node-protocol {
  font-size: 10px;
}
.node-item-card.size-minimal .node-latency {
  font-size: 9px;
}
.node-item-card.size-minimal .node-sub-row {
  margin-top: 2px;
}

/* 卡片文字排版 */
.node-tag {
  font-weight: 500;
  color: var(--md-sys-color-on-surface);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  text-align: left;
}

.node-item-card.selected .node-tag {
  color: var(--md-sys-color-primary);
}

.node-sub-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.node-protocol {
  color: var(--md-sys-color-on-surface-variant);
  opacity: 0.8;
  font-weight: 500;
  text-align: left;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.node-item-card.selected .node-protocol {
  color: var(--md-sys-color-primary);
  opacity: 0.8;
}

.node-latency {
  font-family: var(--md-ref-typeface-mono);
  font-weight: 500;
  padding-left: 8px;
  cursor: pointer;
}

/* 顶栏操作弹出菜单 */
.menu-scrim {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  z-index: 199;
}

.nodes-menu-popup {
  position: fixed;
  top: calc(var(--top-inset) + 54px);
  right: 16px;
  background-color: var(--md-sys-color-surface-container-high);
  border: 1px solid var(--md-sys-color-outline-variant);
  border-radius: var(--radius-xl);
  padding: 8px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  z-index: 200;
  min-width: 180px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  animation: popupScale 0.2s cubic-bezier(0.3, 1, 0.2, 1);
  transform-origin: top right;
}

@keyframes popupScale {
  from { opacity: 0; transform: scale(0.9) translateY(-10px); }
  to { opacity: 1; transform: scale(1) translateY(0); }
}

.menu-item-row {
  display: flex;
  align-items: center;
  width: 100%;
  padding: 10px 16px;
  font-size: 14px;
  font-weight: 500;
  background: transparent;
  border: none;
  text-align: left;
  cursor: pointer;
  color: var(--md-sys-color-on-surface);
  border-radius: var(--radius-sm);
  position: relative;
  overflow: hidden;
}

.menu-item-nested {
  display: flex;
  flex-direction: column;
  padding: 4px 0;
}

.menu-label-header {
  font-size: 11px;
  font-weight: bold;
  color: var(--md-sys-color-primary);
  padding: 4px 16px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.sub-menu-item {
  display: flex;
  align-items: center;
  width: 100%;
  padding: 8px 16px 8px 24px;
  font-size: 13.5px;
  font-weight: 500;
  background: transparent;
  border: none;
  text-align: left;
  cursor: pointer;
  color: var(--md-sys-color-on-surface);
  border-radius: var(--radius-sm);
  position: relative;
  overflow: hidden;
}

.sub-menu-item:hover,
.menu-item-row:hover {
  background-color: var(--md-sys-color-surface-container-highest);
}

.delete-text {
  color: #F44336 !important;
}

.menu-divider {
  height: 1px;
  background-color: var(--md-sys-color-outline-variant);
  margin: 4px 0;
}

/* 弹窗内显示设置偏好行 */
.display-dialog-content {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.preference-group-card {
  background-color: var(--md-sys-color-surface-container);
  border-radius: var(--radius-xl);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.dropdown-pref-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 14px 16px;
  width: 100%;
  box-sizing: border-box;
}

.dropdown-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.dropdown-title {
  font-size: 15px;
  font-weight: 500;
  color: var(--md-sys-color-on-surface);
}

.pref-selector {
  background: var(--md-sys-color-surface-container-high);
  color: var(--md-sys-color-on-surface);
  border: 1px solid var(--md-sys-color-outline-variant);
  padding: 6px 12px;
  border-radius: var(--radius-xs);
  outline: none;
  font-size: 13px;
  cursor: pointer;
}

.pref-inner-divider {
  height: 1px;
  background-color: var(--md-sys-color-outline-variant);
  margin: 0 16px;
  opacity: 0.5;
}

/* 弹窗表单样式 */
.form-dialog-content {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 8px;
}

.form-field {
  width: 100%;
  --md-outlined-text-field-container-shape: var(--radius-md);
}

.delete-item {
  color: #F44336;
}

/* 编辑文件弹窗 */
.edit-dialog {
  --md-dialog-container-width: 90vw;
  --md-dialog-container-max-width: 800px;
}

.editor-content-box {
  width: 100%;
  margin-top: 10px;
}

.raw-json-editor {
  width: 100%;
  height: 380px;
  background: var(--md-sys-color-surface-container-lowest);
  color: var(--md-sys-color-on-surface);
  border: 1px solid var(--md-sys-color-outline);
  border-radius: var(--radius-sm);
  padding: 12px;
  font-family: var(--md-ref-typeface-mono);
  font-size: 12px;
  line-height: 1.5;
  resize: vertical;
}

.raw-json-editor:focus {
  outline: none;
  border-color: var(--md-sys-color-primary);
  border-width: 2px;
}

/* 空状态样式 */
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 48px 0;
  gap: 12px;
}

.empty-icon {
  --md-icon-size: 48px;
  color: var(--md-sys-color-on-surface-variant);
  opacity: 0.5;
}

.empty-icon svg {
  width: 48px;
  height: 48px;
  fill: currentColor;
}

.empty-text {
  font-size: 14px;
  color: var(--md-sys-color-on-surface-variant);
  opacity: 0.7;
}

/* 弹窗容器布局样式 */
.dialogs-wrapper {
  position: absolute;
  width: 0;
  height: 0;
  overflow: visible;
  pointer-events: none;
  z-index: 500;
}

.dialogs-wrapper :deep(md-dialog) {
  pointer-events: auto;
}
</style>
