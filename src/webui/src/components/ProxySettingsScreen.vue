<script setup lang="ts">
/**
 * @file ProxySettingsScreen.vue
 * @description 代理设置子页：透明代理(tproxy)的全部可调项——核心端口/DNS、网络开关、协议、
 *   路由 mark、IP 名单、QUIC/性能、CN-IP 绕过、网卡接口、MAC 过滤。所有状态与写入动作由父级
 *   SettingsLayout 经 provide 注入，本组件只渲染表单并转发；改动写入 tproxy.conf，下次启动/重启生效。
 */
import { inject } from 'vue';
import type { Ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import type { SettingsState } from './SettingsLayout.vue';

const router = useRouter();
const { t } = useI18n();

// 由 SettingsLayout 注入：设置状态 + 布尔开关/下拉/编辑弹窗的处理器
const settingsState = inject<Ref<SettingsState>>('settingsState')!;
const toggleTProxyBool = inject<(key: keyof SettingsState) => Promise<void>>('toggleTProxyBool')!;
const handleDropdownChange = inject<(key: keyof SettingsState, confKey: string, e: Event) => Promise<void>>('handleDropdownChange')!;
const openEditPreference = inject<(key: keyof SettingsState, title: string, label: string, type?: 'text' | 'number') => void>('openEditPreference')!;

/** 返回上一页（子页顶栏返回箭头）。 */
const handleBack = () => {
  router.back();
};
</script>

<template>
  <Teleport to="body">
    <div class="sub-screen-overlay scroll-container">
      <header class="sub-top-bar">
        <div class="sub-top-bar-left">
          <md-icon-button @click="handleBack" class="sub-back-btn">
            <md-icon>
              <svg viewBox="0 0 24 24">
                <path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z" fill="currentColor"/>
              </svg>
            </md-icon>
          </md-icon-button>
          <h1 class="sub-screen-title">{{ t('proxy.title') }}</h1>
        </div>
      </header>

      <div class="sub-screen-content">
        <div class="settings-lazy-column">
          <!-- 核心配置：代理模式 / 端口 / DNS -->
          <div class="small-title">{{ t('proxy.coreConfig') }}</div>
          <div class="config-card">
            <!-- 代理模式下拉（0 自动 / 1 强制 TPROXY / 2 强制 REDIRECT） -->
            <div class="dropdown-pref-row">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyMode') }}</span>
              </div>
              <select :value="settingsState.proxyMode" @change="handleDropdownChange('proxyMode', 'PROXY_MODE', $event)" class="pref-dropdown">
                <option :value="0">{{ t('proxy.modeAuto') }}</option>
                <option :value="1">{{ t('proxy.modeForceTproxy') }}</option>
                <option :value="2">{{ t('proxy.modeForceRedirect') }}</option>
              </select>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('tcpPort', t('proxy.tcpPort'), t('proxy.tcpPortLabel'), 'number')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.tcpPort') }}</span>
                <span class="pref-summary">{{ settingsState.tcpPort || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('udpPort', t('proxy.udpPort'), t('proxy.udpPortLabel'), 'number')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.udpPort') }}</span>
                <span class="pref-summary">{{ settingsState.udpPort || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="switch-pref-row" @click="toggleTProxyBool('dnsHijackEnabled')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.dnsHijack') }}</span>
              </div>
              <md-switch icons :selected="settingsState.dnsHijackEnabled" @click.stop="toggleTProxyBool('dnsHijackEnabled')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('dnsPort', t('proxy.dnsPort'), t('proxy.dnsPortLabel'), 'number')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.dnsPort') }}</span>
                <span class="pref-summary">{{ settingsState.dnsPort || t('common.notSet') }}</span>
              </div>
            </div>
          </div>

          <!-- 网络开关：移动数据 / WiFi / IPv6 -->
          <div class="small-title">{{ t('proxy.networkToggles') }}</div>
          <div class="config-card">
            <div class="switch-pref-row" @click="toggleTProxyBool('proxyMobile')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyMobile') }}</span>
              </div>
              <md-switch icons :selected="settingsState.proxyMobile" @click.stop="toggleTProxyBool('proxyMobile')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="switch-pref-row" @click="toggleTProxyBool('proxyWifi')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyWifi') }}</span>
              </div>
              <md-switch icons :selected="settingsState.proxyWifi" @click.stop="toggleTProxyBool('proxyWifi')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="dropdown-pref-row">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyIpv6') }}</span>
              </div>
              <select :value="settingsState.proxyIpv6" @change="handleDropdownChange('proxyIpv6', 'PROXY_IPV6', $event)" class="pref-dropdown">
                <option :value="0">{{ t('proxy.ipv6Disable') }}</option>
                <option :value="1">{{ t('proxy.ipv6Proxy') }}</option>
                <option :value="-1">{{ t('proxy.ipv6DisableStack') }}</option>
              </select>
            </div>
          </div>

          <!-- 网络协议：TCP / UDP / 热点 / USB 共享 -->
          <div class="small-title">{{ t('proxy.networkProtocols') }}</div>
          <div class="config-card">
            <div class="switch-pref-row" @click="toggleTProxyBool('proxyTcp')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyTcp') }}</span>
              </div>
              <md-switch icons :selected="settingsState.proxyTcp" @click.stop="toggleTProxyBool('proxyTcp')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="switch-pref-row" @click="toggleTProxyBool('proxyUdp')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyUdp') }}</span>
              </div>
              <md-switch icons :selected="settingsState.proxyUdp" @click.stop="toggleTProxyBool('proxyUdp')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="switch-pref-row" @click="toggleTProxyBool('proxyHotspot')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyHotspot') }}</span>
              </div>
              <md-switch icons :selected="settingsState.proxyHotspot" @click.stop="toggleTProxyBool('proxyHotspot')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="switch-pref-row" @click="toggleTProxyBool('proxyUsb')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyUsb') }}</span>
              </div>
              <md-switch icons :selected="settingsState.proxyUsb" @click.stop="toggleTProxyBool('proxyUsb')"></md-switch>
            </div>
          </div>

          <!-- 路由设置：fwmark 与路由表 ID -->
          <div class="small-title">{{ t('proxy.routingSettings') }}</div>
          <div class="config-card">
            <div class="arrow-pref-row" @click="openEditPreference('routingMark', t('proxy.routingMark'), t('proxy.routingMarkLabel'), 'number')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.routingMark') }}</span>
                <span class="pref-summary">{{ settingsState.routingMark || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('markValue', t('proxy.markValue'), t('proxy.markValueLabel'), 'number')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.markValue') }}</span>
                <span class="pref-summary">{{ settingsState.markValue || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('markValue6', t('proxy.markValue6'), t('proxy.markValue6Label'), 'number')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.markValue6') }}</span>
                <span class="pref-summary">{{ settingsState.markValue6 || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('tableId', t('proxy.tableId'), t('proxy.tableIdLabel'), 'number')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.tableId') }}</span>
                <span class="pref-summary">{{ settingsState.tableId || t('common.notSet') }}</span>
              </div>
            </div>
          </div>

          <!-- IP 名单：绕过 / 代理（IPv4 与 IPv6） -->
          <div class="small-title">{{ t('proxy.ipLists') }}</div>
          <div class="config-card">
            <div class="arrow-pref-row" @click="openEditPreference('bypassIpv4List', t('proxy.bypassIpv4'), t('proxy.bypassIpv4Label'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.bypassIpv4') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.bypassIpv4List || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('bypassIpv6List', t('proxy.bypassIpv6'), t('proxy.bypassIpv6Label'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.bypassIpv6') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.bypassIpv6List || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('proxyIpv4List', t('proxy.proxyIpv4'), t('proxy.proxyIpv4Label'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyIpv4') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.proxyIpv4List || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('proxyIpv6List', t('proxy.proxyIpv6'), t('proxy.proxyIpv6Label'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyIpv6') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.proxyIpv6List || t('common.notSet') }}</span>
              </div>
            </div>
          </div>

          <!-- 高级：QUIC 阻断 / 性能模式 / 强制 mark 绕过 -->
          <div class="small-title">{{ t('proxy.advanced') }}</div>
          <div class="config-card">
            <div class="switch-pref-row" @click="toggleTProxyBool('blockQuic')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.blockQuic') }}</span>
              </div>
              <md-switch icons :selected="settingsState.blockQuic" @click.stop="toggleTProxyBool('blockQuic')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="switch-pref-row" @click="toggleTProxyBool('compatibilityMode')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.performanceMode') }}</span>
              </div>
              <md-switch icons :selected="settingsState.compatibilityMode" @click.stop="toggleTProxyBool('compatibilityMode')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="switch-pref-row" @click="toggleTProxyBool('forceMarkBypass')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.forceMarkBypass') }}</span>
              </div>
              <md-switch icons :selected="settingsState.forceMarkBypass" @click.stop="toggleTProxyBool('forceMarkBypass')"></md-switch>
            </div>
          </div>

          <!-- CN-IP（中国大陆 IP）绕过及其数据源 -->
          <div class="small-title">{{ t('proxy.geoBypass') }}</div>
          <div class="config-card">
            <div class="switch-pref-row" @click="toggleTProxyBool('bypassCnIp')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.bypassCnIp') }}</span>
              </div>
              <md-switch icons :selected="settingsState.bypassCnIp" @click.stop="toggleTProxyBool('bypassCnIp')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('cnIpUrl', t('proxy.cnIpUrl'), t('proxy.cnIpUrlLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.cnIpUrl') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.cnIpUrl || t('common.default') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('cnIpv6Url', t('proxy.cnIpv6Url'), t('proxy.cnIpv6UrlLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.cnIpv6Url') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.cnIpv6Url || t('common.default') }}</span>
              </div>
            </div>
          </div>

          <!-- 网卡接口配置：移动 / WiFi / 热点 / USB / 其他 -->
          <div class="small-title">{{ t('proxy.interfaceConfig') }}</div>
          <div class="config-card">
            <div class="arrow-pref-row" @click="openEditPreference('mobileInterface', t('proxy.mobileInterface'), t('proxy.mobileInterfaceLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.mobileInterface') }}</span>
                <span class="pref-summary">{{ settingsState.mobileInterface }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('wifiInterface', t('proxy.wifiInterface'), t('proxy.wifiInterfaceLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.wifiInterface') }}</span>
                <span class="pref-summary">{{ settingsState.wifiInterface }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('hotspotInterface', t('proxy.hotspotInterface'), t('proxy.hotspotInterfaceLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.hotspotInterface') }}</span>
                <span class="pref-summary">{{ settingsState.hotspotInterface }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('usbInterface', t('proxy.usbInterface'), t('proxy.usbInterfaceLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.usbInterface') }}</span>
                <span class="pref-summary">{{ settingsState.usbInterface }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('otherProxyInterfaces', t('proxy.otherProxyInterfaces'), t('proxy.otherProxyInterfacesLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.otherProxyInterfaces') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.otherProxyInterfaces || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('otherBypassInterfaces', t('proxy.otherBypassInterfaces'), t('proxy.otherBypassInterfacesLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.otherBypassInterfaces') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.otherBypassInterfaces || t('common.notSet') }}</span>
              </div>
            </div>
          </div>

          <!-- MAC 地址过滤：开关 / 模式 / 名单 -->
          <div class="small-title">{{ t('proxy.macFiltering') }}</div>
          <div class="config-card">
            <div class="switch-pref-row" @click="toggleTProxyBool('macFilterEnable')">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.macFilterEnable') }}</span>
              </div>
              <md-switch icons :selected="settingsState.macFilterEnable" @click.stop="toggleTProxyBool('macFilterEnable')"></md-switch>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="dropdown-pref-row">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.filterMode') }}</span>
              </div>
              <select :value="settingsState.macProxyMode" @change="handleDropdownChange('macProxyMode', 'MAC_PROXY_MODE', $event)" class="pref-dropdown">
                <option value="blacklist">{{ t('proxy.filterBlacklist') }}</option>
                <option value="whitelist">{{ t('proxy.filterWhitelist') }}</option>
              </select>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('proxyMacsList', t('proxy.proxyMacs'), t('proxy.proxyMacsLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.proxyMacs') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.proxyMacsList || t('common.notSet') }}</span>
              </div>
            </div>

            <div class="pref-inner-divider"></div>

            <div class="arrow-pref-row" @click="openEditPreference('bypassMacsList', t('proxy.bypassMacs'), t('proxy.bypassMacsLabel'))">
              <div class="pref-text">
                <span class="pref-title">{{ t('proxy.bypassMacs') }}</span>
                <span class="pref-summary text-ellipsis">{{ settingsState.bypassMacsList || t('common.notSet') }}</span>
              </div>
            </div>
          </div>
          
          <div class="bottom-padding-spacer"></div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* 子页覆盖层与顶栏（与原 SettingsScreen 一致的层叠样式） */
.sub-screen-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  width: 100vw;
  height: 100vh;
  background-color: var(--md-sys-color-background);
  z-index: 9999;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  overflow: hidden;
  animation: slideUp 0.3s cubic-bezier(0.2, 0.8, 0.2, 1) forwards;
}

@keyframes slideUp {
  from {
    opacity: 0;
    transform: translateY(30px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.sub-top-bar {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: calc(64px + var(--top-inset));
  padding-top: var(--top-inset);
  padding-left: 16px;
  padding-right: 16px;
  color: var(--md-sys-color-on-background);
  background-color: var(--md-sys-color-background);
  border-bottom: 1px solid var(--md-sys-color-outline-variant);
  box-sizing: border-box;
  width: 100%;
}

.sub-top-bar-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.sub-back-btn {
  --md-icon-button-container-width: 40px;
  --md-icon-button-container-height: 40px;
}

.sub-screen-title {
  font-size: 20px;
  font-weight: 550;
  margin: 0;
}

.sub-screen-content {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 16px;
  padding-bottom: calc(24px + var(--bottom-inset));
  box-sizing: border-box;
  width: 100%;
}

.settings-lazy-column {
  display: flex;
  flex-direction: column;
  gap: 12px;
  width: 100%;
  max-width: 800px;
  margin: 0 auto;
}

.settings-lazy-column .config-card {
  padding: 0;
  gap: 0;
  overflow: hidden;
  background-color: var(--md-sys-color-surface-container);
  border-radius: var(--radius-xl);
  border: none;
  display: flex;
  flex-direction: column;
}

.bottom-padding-spacer {
  height: 40px;
}

/* 分组小标题 */
.small-title {
  font-size: 13.5px;
  font-weight: 600;
  color: var(--md-sys-color-primary);
  margin-top: 14px;
  margin-bottom: 4px;
  padding-left: 12px;
  text-transform: uppercase;
}

.arrow-pref-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  gap: 14px;
  padding: 14px 16px;
  cursor: pointer;
  box-sizing: border-box;
  transition: background-color 0.2s;
}

.arrow-pref-row:hover {
  background-color: var(--md-sys-color-surface-container-high);
}

.switch-pref-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  gap: 14px;
  padding: 14px 16px;
  cursor: pointer;
  box-sizing: border-box;
  transition: background-color 0.2s;
}

.switch-pref-row:hover {
  background-color: var(--md-sys-color-surface-container-high);
}

.dropdown-pref-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  gap: 14px;
  padding: 14px 16px;
  box-sizing: border-box;
}

.pref-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  flex-grow: 1;
  min-width: 0;
}

.pref-title {
  font-size: 15.5px;
  font-weight: 500;
  color: var(--md-sys-color-on-surface);
}

.pref-summary {
  font-size: 12.5px;
  color: var(--md-sys-color-on-surface-variant);
}

.text-ellipsis {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.pref-dropdown {
  background-color: var(--md-sys-color-surface-container-high);
  color: var(--md-sys-color-on-surface);
  border: 1px solid var(--md-sys-color-outline-variant);
  padding: 6px 12px;
  border-radius: var(--radius-sm);
  outline: none;
  font-size: 13.5px;
  font-weight: 500;
  cursor: pointer;
  appearance: none;
}

.pref-inner-divider {
  display: none;
}
</style>
