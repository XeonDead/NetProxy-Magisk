<script setup lang="ts">
/**
 * @file SettingsLayout.vue
 * @description 设置页布局兼「控制器」：持有聚合设置状态(SettingsState)，负责读写 module.conf 与
 *   tproxy.conf，并把状态与各类切换/编辑动作经 provide 下发给子页（SettingsMain / ProxySettings 等）。
 *   自身只渲染 router-view 与一个通用文本编辑弹窗。非真机环境用 localStorage 模拟持久化。
 */
import { ref, provide, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { showToast, readFileContent, writeFileContent, isKsuEnv } from '../utils/ksu';
import { useBackDismiss } from '../composables/useBackDismiss';

const { t } = useI18n();

/** 设置页聚合状态：module.conf（自启/选择器/GMS）+ tproxy.conf（透明代理全部可调项）的镜像。 */
export interface SettingsState {
  autoStartEnabled: boolean;
  selectorUrlTestEnabled: boolean;
  gmsFixEnabled: boolean;
  
  proxyMode: number;
  tcpPort: string;
  udpPort: string;
  dnsHijackEnabled: boolean;
  dnsPort: string;
  proxyMobile: boolean;
  proxyWifi: boolean;
  proxyIpv6: number;
  proxyTcp: boolean;
  proxyUdp: boolean;
  proxyHotspot: boolean;
  proxyUsb: boolean;
  routingMark: string;
  markValue: string;
  markValue6: string;
  tableId: string;
  bypassIpv4List: string;
  bypassIpv6List: string;
  proxyIpv4List: string;
  proxyIpv6List: string;
  blockQuic: boolean;
  compatibilityMode: boolean; // PERFORMANCE_MODE
  forceMarkBypass: boolean;
  bypassCnIp: boolean;
  cnIpUrl: string;
  cnIpv6Url: string;
  mobileInterface: string;
  wifiInterface: string;
  hotspotInterface: string;
  usbInterface: string;
  otherProxyInterfaces: string;
  otherBypassInterfaces: string;
  macFilterEnable: boolean;
  macProxyMode: string;
  proxyMacsList: string;
  bypassMacsList: string;
}

// 设置状态（含默认值），onMounted 后由 loadSettings 用配置文件实际值覆盖
const settingsState = ref<SettingsState>({
  autoStartEnabled: false,
  selectorUrlTestEnabled: false,
  gmsFixEnabled: false,
  
  proxyMode: 0,
  tcpPort: '12345',
  udpPort: '12345',
  dnsHijackEnabled: false,
  dnsPort: '1053',
  proxyMobile: false,
  proxyWifi: false,
  proxyIpv6: 0,
  proxyTcp: false,
  proxyUdp: false,
  proxyHotspot: false,
  proxyUsb: false,
  routingMark: '',
  markValue: '20',
  markValue6: '25',
  tableId: '2025',
  bypassIpv4List: '',
  bypassIpv6List: '',
  proxyIpv4List: '',
  proxyIpv6List: '',
  blockQuic: false,
  compatibilityMode: false,
  forceMarkBypass: false,
  bypassCnIp: false,
  cnIpUrl: '',
  cnIpv6Url: '',
  mobileInterface: 'rmnet_data+',
  wifiInterface: 'wlan0',
  hotspotInterface: 'wlan2',
  usbInterface: 'rndis+',
  otherProxyInterfaces: '',
  otherBypassInterfaces: '',
  macFilterEnable: false,
  macProxyMode: 'blacklist',
  proxyMacsList: '',
  bypassMacsList: ''
});

// 通用编辑输入框弹窗状态（被各设置子页的「编辑」项复用）
const showEditDialog = ref(false);
const editKey = ref('');
const editTitle = ref('');
const editLabel = ref('');
const editValue = ref('');
const editType = ref<'text' | 'number'>('text');

// 手势返回优先关闭编辑输入框对话框（覆盖各设置子页的输入框）
useBackDismiss(
  () => showEditDialog.value,
  () => { showEditDialog.value = false; }
);

// ===================================================================
// 配置文件解析 / 写入
// ===================================================================

/**
 * 解析 KEY=value 配置文件为对象（跳过空行与 # 注释，去除值两侧引号）。
 * @param content  配置文件全文
 * @returns 键值对象
 */
const parseConfigFile = (content: string): Record<string, string> => {
  const result: Record<string, string> = {};
  const lines = content.split('\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx === -1) continue;
    const key = trimmed.substring(0, eqIdx).trim();
    let val = trimmed.substring(eqIdx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.substring(1, val.length - 1);
    }
    result[key] = val;
  }
  return result;
};

/**
 * 在配置全文中就地改写某个键的值（键不存在则追加），保留其余行不动。
 * @param content      配置文件全文
 * @param key          目标键
 * @param value        新值
 * @param forceQuotes  是否给值加双引号（含空格的列表/字符串用）
 * @returns 改写后的全文
 */
const writeConfigValue = (content: string, key: string, value: string, forceQuotes = false): string => {
  const lines = content.split('\n');
  let found = false;
  const newValue = forceQuotes ? `"${value}"` : value;
  
  const newLines = lines.map(line => {
    const trimmed = line.trim();
    if (trimmed.startsWith('#')) return line;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx === -1) return line;
    const currentKey = trimmed.substring(0, eqIdx).trim();
    if (currentKey === key) {
      found = true;
      return `${key}=${newValue}`;
    }
    return line;
  });
  
  if (!found) {
    newLines.push(`${key}=${newValue}`);
  }
  return newLines.join('\n');
};

/**
 * 把驼峰状态键映射为 tproxy.conf 的下划线大写键（少数特例硬编码）。
 * @param key  SettingsState 字段名
 * @returns 配置文件键名
 */
const stateKeyToConfKey = (key: string): string => {
  if (key === 'tcpPort') return 'PROXY_TCP_PORT';
  if (key === 'udpPort') return 'PROXY_UDP_PORT';
  if (key === 'dnsPort') return 'DNS_PORT';
  if (key === 'compatibilityMode') return 'PERFORMANCE_MODE';
  return key.replace(/([A-Z])/g, "_$1").toUpperCase();
};

// ===================================================================
// 加载设置 / 写入设置
// ===================================================================

/** 从 module.conf 与 tproxy.conf 读取全部设置填入状态；真机读取失败时回退 localStorage mock。 */
const loadSettings = async () => {
  try {
    // 1. 读取 module.conf（模块侧：自启 / 选择器模式 / GMS 修复）
    const moduleConfContent = await readFileContent('/data/adb/modules/netproxy/config/module.conf');
    const moduleConf = parseConfigFile(moduleConfContent);
    settingsState.value.autoStartEnabled = moduleConf['AUTO_START'] !== '0';
    settingsState.value.selectorUrlTestEnabled = moduleConf['SELECTOR_MODE'] !== 'manual';
    settingsState.value.gmsFixEnabled = moduleConf['GMS_FIX'] === '1';

    // 2. 读取 tproxy.conf（网络侧：透明代理全部参数）
    const tproxyConfContent = await readFileContent('/data/adb/modules/netproxy/config/tproxy/tproxy.conf');
    const tproxyConf = parseConfigFile(tproxyConfContent);
    
    const getBool = (key: string) => tproxyConf[key] === '1';
    const getInt = (key: string, def = 0) => parseInt(tproxyConf[key] || String(def)) || def;
    const getVal = (key: string, def = '') => tproxyConf[key] !== undefined ? tproxyConf[key] : def;

    settingsState.value.proxyMode = getInt('PROXY_MODE', 0);
    settingsState.value.tcpPort = getVal('PROXY_TCP_PORT', '12345');
    settingsState.value.udpPort = getVal('PROXY_UDP_PORT', '12345');
    settingsState.value.dnsHijackEnabled = getBool('DNS_HIJACK_ENABLE');
    settingsState.value.dnsPort = getVal('DNS_PORT', '1053');
    settingsState.value.proxyMobile = getBool('PROXY_MOBILE');
    settingsState.value.proxyWifi = getBool('PROXY_WIFI');
    settingsState.value.proxyIpv6 = getInt('PROXY_IPV6', 0);
    settingsState.value.proxyTcp = getBool('PROXY_TCP');
    settingsState.value.proxyUdp = getBool('PROXY_UDP');
    settingsState.value.proxyHotspot = getBool('PROXY_HOTSPOT');
    settingsState.value.proxyUsb = getBool('PROXY_USB');
    settingsState.value.routingMark = getVal('ROUTING_MARK', '');
    settingsState.value.markValue = getVal('MARK_VALUE', '20');
    settingsState.value.markValue6 = getVal('MARK_VALUE6', '25');
    settingsState.value.tableId = getVal('TABLE_ID', '2025');
    settingsState.value.bypassIpv4List = getVal('BYPASS_IPv4_LIST', '');
    settingsState.value.bypassIpv6List = getVal('BYPASS_IPv6_LIST', '');
    settingsState.value.proxyIpv4List = getVal('PROXY_IPv4_LIST', '');
    settingsState.value.proxyIpv6List = getVal('PROXY_IPv6_LIST', '');
    settingsState.value.blockQuic = getBool('BLOCK_QUIC');
    settingsState.value.compatibilityMode = getBool('PERFORMANCE_MODE');
    settingsState.value.forceMarkBypass = getBool('FORCE_MARK_BYPASS');
    settingsState.value.bypassCnIp = getBool('BYPASS_CN_IP');
    settingsState.value.cnIpUrl = getVal('CN_IP_URL', '');
    settingsState.value.cnIpv6Url = getVal('CN_IPV6_URL', '');
    settingsState.value.mobileInterface = getVal('MOBILE_INTERFACE', 'rmnet_data+');
    settingsState.value.wifiInterface = getVal('WIFI_INTERFACE', 'wlan0');
    settingsState.value.hotspotInterface = getVal('HOTSPOT_INTERFACE', 'wlan2');
    settingsState.value.usbInterface = getVal('USB_INTERFACE', 'rndis+');
    settingsState.value.otherProxyInterfaces = getVal('OTHER_PROXY_INTERFACES', '');
    settingsState.value.otherBypassInterfaces = getVal('OTHER_BYPASS_INTERFACES', '');
    settingsState.value.macFilterEnable = getBool('MAC_FILTER_ENABLE');
    settingsState.value.macProxyMode = getVal('MAC_PROXY_MODE', 'blacklist');
    settingsState.value.proxyMacsList = getVal('PROXY_MACS_LIST', '');
    settingsState.value.bypassMacsList = getVal('BYPASS_MACS_LIST', '');

  } catch (e) {
    console.warn('Failed to load native configs, using mock persistence:', e);
    const getMockBool = (key: string, def = false) => localStorage.getItem(`mock_settings_${key}`) === 'true' || (localStorage.getItem(`mock_settings_${key}`) === null && def);
    const getMockInt = (key: string, def = 0) => parseInt(localStorage.getItem(`mock_settings_${key}`) || String(def));
    const getMockVal = (key: string, def = '') => localStorage.getItem(`mock_settings_${key}`) !== null ? localStorage.getItem(`mock_settings_${key}`) as string : def;

    settingsState.value.autoStartEnabled = getMockBool('autoStartEnabled');
    settingsState.value.selectorUrlTestEnabled = getMockBool('selectorUrlTestEnabled');
    settingsState.value.gmsFixEnabled = getMockBool('gmsFixEnabled');
    settingsState.value.proxyMode = getMockInt('proxyMode', 0);
    settingsState.value.tcpPort = getMockVal('tcpPort', '12345');
    settingsState.value.udpPort = getMockVal('udpPort', '12345');
    settingsState.value.dnsHijackEnabled = getMockBool('dnsHijackEnabled', true);
    settingsState.value.dnsPort = getMockVal('dnsPort', '1053');
    settingsState.value.proxyMobile = getMockBool('proxyMobile');
    settingsState.value.proxyWifi = getMockBool('proxyWifi', true);
    settingsState.value.proxyIpv6 = getMockInt('proxyIpv6', 0);
    settingsState.value.proxyTcp = getMockBool('proxyTcp', true);
    settingsState.value.proxyUdp = getMockBool('proxyUdp', true);
    settingsState.value.proxyHotspot = getMockBool('proxyHotspot');
    settingsState.value.proxyUsb = getMockBool('proxyUsb');
    settingsState.value.routingMark = getMockVal('routingMark', '80');
    settingsState.value.markValue = getMockVal('markValue', '20');
    settingsState.value.markValue6 = getMockVal('markValue6', '25');
    settingsState.value.tableId = getMockVal('tableId', '2025');
    settingsState.value.bypassIpv4List = getMockVal('bypassIpv4List', '192.168.0.0/16,10.0.0.0/8');
    settingsState.value.bypassIpv6List = getMockVal('bypassIpv6List', 'fe80::/10');
    settingsState.value.proxyIpv4List = getMockVal('proxyIpv4List', '');
    settingsState.value.proxyIpv6List = getMockVal('proxyIpv6List', '');
    settingsState.value.blockQuic = getMockBool('blockQuic', true);
    settingsState.value.compatibilityMode = getMockBool('compatibilityMode');
    settingsState.value.forceMarkBypass = getMockBool('forceMarkBypass', true);
    settingsState.value.bypassCnIp = getMockBool('bypassCnIp', true);
    settingsState.value.cnIpUrl = getMockVal('cnIpUrl', '');
    settingsState.value.cnIpv6Url = getMockVal('cnIpv6Url', '');
    settingsState.value.mobileInterface = getMockVal('mobileInterface', 'rmnet_data+');
    settingsState.value.wifiInterface = getMockVal('wifiInterface', 'wlan0');
    settingsState.value.hotspotInterface = getMockVal('hotspotInterface', 'wlan2');
    settingsState.value.usbInterface = getMockVal('usbInterface', 'rndis+');
    settingsState.value.otherProxyInterfaces = getMockVal('otherProxyInterfaces', '');
    settingsState.value.otherBypassInterfaces = getMockVal('otherBypassInterfaces', '');
    settingsState.value.macFilterEnable = getMockBool('macFilterEnable');
    settingsState.value.macProxyMode = getMockVal('macProxyMode', 'blacklist');
    settingsState.value.proxyMacsList = getMockVal('proxyMacsList', '');
    settingsState.value.bypassMacsList = getMockVal('bypassMacsList', '');
  }
};

/**
 * 写入 module.conf 的单个键（真机改文件，mock 写 localStorage）。
 * @param key    配置键（AUTO_START / SELECTOR_MODE / GMS_FIX）
 * @param value  新值
 */
const updateModuleSetting = async (key: string, value: string) => {
  if (isKsuEnv()) {
    const path = '/data/adb/modules/netproxy/config/module.conf';
    try {
      const content = await readFileContent(path);
      const newContent = writeConfigValue(content, key, value);
      await writeFileContent(path, newContent);
    } catch (e) {
      console.error(`Failed to update ${key} in module.conf:`, e);
      showToast(t('settings.updateModuleFailed'));
    }
  } else {
    const map: Record<string, string> = {
      'AUTO_START': 'autoStartEnabled',
      'SELECTOR_MODE': 'selectorUrlTestEnabled',
      'GMS_FIX': 'gmsFixEnabled'
    };
    const stateKey = map[key];
    if (stateKey) {
      const boolVal = key === 'SELECTOR_MODE' ? value === 'urltest' : value === '1';
      localStorage.setItem(`mock_settings_${stateKey}`, String(boolVal));
    }
  }
};

/**
 * 写入 tproxy.conf 的单个键（真机改文件，mock 写 localStorage）。只写文件、不重载规则，下次启动/重启生效。
 * @param key          配置键
 * @param value        新值
 * @param forceQuotes  是否给值加双引号
 */
const updateTProxySetting = async (key: string, value: string, forceQuotes = false) => {
  if (isKsuEnv()) {
    const path = '/data/adb/modules/netproxy/config/tproxy/tproxy.conf';
    try {
      const content = await readFileContent(path);
      const newContent = writeConfigValue(content, key, value, forceQuotes);
      await writeFileContent(path, newContent);
      // 仅写入配置文件，不触发 tproxy 规则重载；改动将在下次服务启动/重启时生效
    } catch (e) {
      console.error(`Failed to update ${key} in tproxy.conf:`, e);
      showToast(t('settings.updateTproxyFailed'));
    }
  } else {
    let stateKey = '';
    const keys = Object.keys(settingsState.value);
    for (const k of keys) {
      if (stateKeyToConfKey(k) === key) {
        stateKey = k;
        break;
      }
    }
    if (stateKey) {
      localStorage.setItem(`mock_settings_${stateKey}`, value);
    }
  }
};

// ===================================================================
// 开关 / 下拉 / 编辑等动作（经 provide 下发给子页）
// ===================================================================

/** 切换「开机自启」并写入 module.conf。 */
const toggleAutoStart = async () => {
  const val = !settingsState.value.autoStartEnabled;
  settingsState.value.autoStartEnabled = val;
  await updateModuleSetting('AUTO_START', val ? '1' : '0');
  showToast(val ? t('settings.autoStartOn') : t('settings.autoStartOff'));
};

/** 切换选择器模式（urltest 自动测速 / manual 手动）并写入 module.conf。 */
const toggleSelectorUrlTest = async () => {
  const val = !settingsState.value.selectorUrlTestEnabled;
  settingsState.value.selectorUrlTestEnabled = val;
  await updateModuleSetting('SELECTOR_MODE', val ? 'urltest' : 'manual');
  showToast(val ? t('settings.urltestOn') : t('settings.urltestOff'));
};

/** 切换「GMS 修复」并写入 module.conf。 */
const toggleGmsFix = async () => {
  const val = !settingsState.value.gmsFixEnabled;
  settingsState.value.gmsFixEnabled = val;
  await updateModuleSetting('GMS_FIX', val ? '1' : '0');
  showToast(val ? t('settings.gmsFixOn') : t('settings.gmsFixOff'));
};

/**
 * 切换某个 tproxy 布尔项（取反 → 写 1/0）。
 * @param key  SettingsState 中的布尔字段
 */
const toggleTProxyBool = async (key: keyof SettingsState) => {
  const val = !settingsState.value[key];
  (settingsState.value as any)[key] = val;
  const confKey = stateKeyToConfKey(key);
  await updateTProxySetting(confKey, val ? '1' : '0');
  showToast(t('settings.prefUpdated'));
};

/**
 * 下拉选择变更：更新状态并写入对应 tproxy 键（数值串自动转 number）。
 * @param key      SettingsState 字段
 * @param confKey  对应 tproxy.conf 键
 * @param e        select 的 change 事件
 */
const handleDropdownChange = async (key: keyof SettingsState, confKey: string, e: Event) => {
  const select = e.target as HTMLSelectElement;
  const val = select.value;
  (settingsState.value as any)[key] = isNaN(Number(val)) ? val : Number(val);
  await updateTProxySetting(confKey, val);
  showToast(t('settings.prefUpdated'));
};

/**
 * 打开通用文本编辑弹窗，载入指定项的当前值。
 * @param key    SettingsState 字段
 * @param title  弹窗标题
 * @param label  输入框标签
 * @param type   输入类型（text / number）
 */
const openEditPreference = (key: keyof SettingsState, title: string, label: string, type: 'text' | 'number' = 'text') => {
  editKey.value = key;
  editTitle.value = title;
  editLabel.value = label;
  editValue.value = String(settingsState.value[key]);
  editType.value = type;
  showEditDialog.value = true;
};

/** 保存编辑弹窗的值：写回状态并写入 tproxy.conf（端口/列表/接口等键强制加引号）。 */
const handleSaveEdit = async () => {
  const key = editKey.value as keyof SettingsState;
  const val = editValue.value.trim();
  
  (settingsState.value as any)[key] = val;
  const confKey = stateKeyToConfKey(key);
  const forceQuotes = ['PORT', 'MARK', 'ID', 'LIST', 'INTERFACE', 'URL'].some(keyword => confKey.toUpperCase().includes(keyword));
  
  await updateTProxySetting(confKey, val, forceQuotes);
  showEditDialog.value = false;
  showToast(t('settings.savedItem', { title: editTitle.value }));
};

onMounted(() => {
  loadSettings();
});

// 向设置子页（router-view 子组件）下发状态与处理函数
provide('settingsState', settingsState);
provide('toggleAutoStart', toggleAutoStart);
provide('toggleSelectorUrlTest', toggleSelectorUrlTest);
provide('toggleGmsFix', toggleGmsFix);
provide('toggleTProxyBool', toggleTProxyBool);
provide('handleDropdownChange', handleDropdownChange);
provide('openEditPreference', openEditPreference);
provide('updateTProxySetting', updateTProxySetting);
</script>

<template>
  <div class="settings-layout-wrapper">
    <!-- 渲染设置子页 -->
    <router-view v-slot="{ Component }">
      <component :is="Component" />
    </router-view>

    <!-- 通用文本设置项编辑弹窗 -->
    <md-dialog :open="showEditDialog" @close="showEditDialog = false" class="transparent-scrim">
      <div slot="headline">{{ editTitle }}</div>
      <div slot="content" class="display-dialog-content">
        <md-outlined-text-field
          class="edit-text-field"
          :label="editLabel"
          :type="editType"
          v-model="editValue"
          autofocus>
        </md-outlined-text-field>
      </div>
      <div slot="actions">
        <md-text-button @click="showEditDialog = false">{{ t('common.cancel') }}</md-text-button>
        <md-text-button @click="handleSaveEdit">{{ t('common.save') }}</md-text-button>
      </div>
    </md-dialog>
  </div>
</template>

<style scoped>
.settings-layout-wrapper {
  width: 100%;
  height: 100%;
}

.display-dialog-content {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 8px;
}

.edit-text-field {
  width: 100%;
}

.transparent-scrim {
  --md-dialog-scrim-color: rgba(0, 0, 0, 0.4);
}
</style>
