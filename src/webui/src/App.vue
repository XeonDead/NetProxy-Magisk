<script setup lang="ts">
/**
 * @file App.vue
 * @description 应用根布局：顶栏（标题 + 节点/应用页操作按钮）、主内容区（router-view + keep-alive
 *   缓存四个主页面）、底部 tab 导航。集中处理 tab 切换的历史深度策略、软键盘弹出检测与 edge-to-edge。
 */
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { setEdgeToEdge } from './utils/ksu';
import '@material/web/icon/icon.js';

type TabId = 'dashboard' | 'nodes' | 'bypass' | 'config';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

// 当前激活的主 tab：由路由路径反推（用于底栏高亮与顶栏标题）
const activeTab = computed<TabId>(() => {
  const path = route.path;
  if (path.startsWith('/nodes')) return 'nodes';
  if (path.startsWith('/bypass')) return 'bypass';
  if (path.startsWith('/settings')) return 'config';
  return 'dashboard';
});

const hideBottomNav = computed(() => {
  // 子页(showBack)或软键盘弹出时隐藏底栏：
  // WebView adjustResize 下键盘会压缩视口，position:fixed 的底栏会被顶到键盘上方
  return route.meta.showBack === true || keyboardOpen.value;
});

// 顶栏只在子页隐藏；键盘弹出时保留顶栏（键盘只影响底部）
const hideTopBar = computed(() => route.meta.showBack === true);

// 主内容区高度：子页全屏；键盘弹出时仅扣顶栏(底栏已隐藏)；常态扣顶栏+底栏
const mainHeight = computed(() => {
  if (hideTopBar.value) return '100vh';
  if (keyboardOpen.value) return 'calc(100vh - 64px - var(--top-inset))';
  return 'calc(100vh - 64px - var(--top-inset) - var(--bottom-nav-height) - var(--bottom-inset))';
});

// 软键盘是否弹出：记录"全屏高度基线"（未弹键盘时见过的最大可视高度），
// 当前可视高度比基线矮 150px 以上即判定键盘弹出。
// 注：adjustResize 模式下键盘弹出时 innerHeight 与 visualViewport.height 同步缩小，
//     两者相减恒为 0，故不能用差值，必须与基线比。
const keyboardOpen = ref(false);
let viewportBaseline = 0;
const currentViewportH = () => window.visualViewport?.height ?? window.innerHeight;

const onViewportResize = () => {
  const h = currentViewportH();
  // 高度增大（键盘收起 / 旋转到更高视口）时刷新基线，使其自校正为真实全屏高度
  if (h > viewportBaseline) {
    viewportBaseline = h;
    keyboardOpen.value = false;
    return;
  }
  keyboardOpen.value = (viewportBaseline - h) > 150;
};

// 主 tab 标题随语言切换：按当前 tab 取 nav.* 文案（子页有自己的顶栏标题，此处不显示）
const screenTitle = computed(() => {
  const map: Record<TabId, string> = {
    dashboard: 'nav.dashboard',
    nodes: 'nav.nodes',
    bypass: 'nav.apps',
    config: 'nav.settings'
  };
  return t(map[activeTab.value]);
});

/**
 * 切换主 tab，并按历史深度策略选择 push/replace/back（策略详见内部注释）。
 * @param tab  目标 tab
 */
const handleTabChange = (tab: TabId) => {
  if (tab === activeTab.value) return;

  const pathMap = {
    dashboard: '/dashboard',
    nodes: '/nodes',
    bypass: '/bypass',
    config: '/settings'
  };

  // 历史深度策略，保证「主 tab 返回→仪表盘，仪表盘返回→退出」：
  //  - 去仪表盘：back() 弹出栈顶回到底部仪表盘（深度→1，再返回则 canGoBack=false 退出）
  //  - 仪表盘→其它 tab：push（深度 1→2）
  //  - 其它 tab 之间：replace（保持深度 2，返回仍回仪表盘，不累积链）
  if (tab === 'dashboard') {
    router.back();
  } else if (activeTab.value === 'dashboard') {
    router.push(pathMap[tab]);
  } else {
    router.replace(pathMap[tab]);
  }
};

// 当前页面组件实例引用：顶栏操作按钮借此调用子页暴露的方法（打开设置/菜单）
const activeComponentRef = ref<any>(null);

/** 记录 router-view 当前页面组件实例。 */
const setComponentRef = (el: any) => {
  activeComponentRef.value = el;
};

/** 触发节点页「显示设置」弹窗。 */
const triggerNodesSettings = () => {
  activeComponentRef.value?.openDisplaySettings();
};

/** 触发节点页菜单。 */
const triggerNodesMenu = () => {
  activeComponentRef.value?.openNodesMenu();
};

/** 触发应用页菜单。 */
const triggerBypassMenu = () => {
  activeComponentRef.value?.openAppsMenu();
};

// 底部导航图标的 SVG 路径（regular = 未选中描边，filled = 选中实心）
const icons = {
  dashboard: {
    regular: "M12 5.69l5 3.64v8.67h-2v-6H9v6H7v-8.67l5-3.64M12 3L2 12h3v8h6v-6h2v6h6v-8h3L12 3z",
    filled: "M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"
  },
  nodes: {
    regular: "M20 13H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1v-6c0-.55-.45-1-1-1zm-1 6H5v-4h14v4zM20 3H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1V4c0-.55-.45-1-1-1zm-1 6H5V5h14v4z",
    filled: "M20 13H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1v-6c0-.55-.45-1-1-1zM20 3H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1V4c0-.55-.45-1-1-1z"
  },
  bypass: {
    regular: "M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z",
    filled: "M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z"
  },
  config: {
    regular: "M19.43 12.98c.04-.32.07-.64.07-.98s-.03-.66-.07-.98l2.11-1.65c.19-.15.24-.42.12-.64l-2-3.46c-.12-.22-.39-.3-.61-.22l-2.49 1c-.52-.4-1.08-.73-1.69-.98l-.38-2.65C14.46 2.18 14.25 2 14 2h-4c-.25 0-.46.18-.49.42l-.38 2.65c-.61.25-1.17.59-1.69.98l-2.49-1c-.23-.09-.49 0-.61.22l-2 3.46c-.13.22-.07.49.12.64l2.11 1.65c-.04.32-.07.65-.07.98s.03.66.07.98l-2.11 1.65c-.19.15-.24.42-.12.64l2 3.46c.12.22.39.3.61.22l2.49-1c.52.4 1.08.73 1.69.98l.38 2.65c.03.24.24.42.49.42h4c.25 0 .46-.18.49-.42l.38-2.65c.61-.25 1.17-.59 1.69-.98l2.49 1c.23.09.49 0 .61-.22l2-3.46c.12-.22.07-.49-.12-.64l-2.11-1.65zM12 15.5c-1.93 0-3.5-1.57-3.5-3.5s1.57-3.5 3.5-3.5 3.5 1.57 3.5 3.5-1.57 3.5-3.5 3.5zM12 12c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z",
    filled: "M12 12c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z M19.43 12.98c.04-.32.07-.64.07-.98s-.03-.66-.07-.98l2.11-1.65c.19-.15.24-.42.12-.64l-2-3.46c-.12-.22-.39-.3-.61-.22l-2.49 1c-.52-.4-1.08-.73-1.69-.98l-.38-2.65C14.46 2.18 14.25 2 14 2h-4c-.25 0-.46.18-.49.42l-.38 2.65c-.61.25-1.17.59-1.69.98l-2.49-1c-.23-.09-.49 0-.61.22l-2 3.46c-.13.22-.07.49.12.64l2.11 1.65c-.04.32-.07.65-.07.98s.03.66.07.98l-2.11 1.65c-.19.15-.24.42-.12.64l2 3.46c.12.22.39.3.61.22l2.49-1c.52.4 1.08.73 1.69.98l.38 2.65c.03.24.24.42.49.42h4c.25 0 .46-.18.49-.42l.38-2.65c.61-.25 1.17-.59 1.69-.98l2.49 1c.23.09.49 0 .61-.22l2-3.46c.12-.22.07-.49-.12-.64l-2.11-1.65zM12 15.5c-1.93 0-3.5-1.57-3.5-3.5s1.57-3.5 3.5-3.5 3.5 1.57 3.5 3.5-1.57 3.5-3.5 3.5z"
  }
};

// 顶栏操作图标 (齿轮复用 config 图标，竖三点菜单)
const topIcons = {
  gear: "M19.43 12.98c.04-.32.07-.64.07-.98s-.03-.66-.07-.98l2.11-1.65c.19-.15.24-.42.12-.64l-2-3.46c-.12-.22-.39-.3-.61-.22l-2.49 1c-.52-.4-1.08-.73-1.69-.98l-.38-2.65C14.46 2.18 14.25 2 14 2h-4c-.25 0-.46.18-.49.42l-.38 2.65c-.61.25-1.17.59-1.69.98l-2.49-1c-.23-.09-.49 0-.61.22l-2 3.46c-.13.22-.07.49.12.64l2.11 1.65c-.04.32-.07.65-.07.98s.03.66.07.98l-2.11 1.65c-.19.15-.24.42-.12.64l2 3.46c.12.22.39.3.61.22l2.49-1c.52.4 1.08.73 1.69.98l.38 2.65c.03.24.24.42.49.42h4c.25 0 .46-.18.49-.42l.38-2.65c.61-.25 1.17-.59 1.69-.98l2.49 1c.23.09.49 0 .61-.22l2-3.46c.12-.22.07-.49-.12-.64l-2.11-1.65zM12 15.5c-1.93 0-3.5-1.57-3.5-3.5s1.57-3.5 3.5-3.5 3.5 1.57 3.5 3.5-1.57 3.5-3.5 3.5z",
  menu: "M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"
};

onMounted(() => {
  setEdgeToEdge(true);
  // 初始化基线为当前可视高度（此刻键盘未弹出）
  viewportBaseline = currentViewportH();
  // 同时监听 visualViewport 与 window：不同 WebView 键盘弹出触发的事件源不一致
  window.visualViewport?.addEventListener('resize', onViewportResize);
  window.addEventListener('resize', onViewportResize);
});

onUnmounted(() => {
  window.visualViewport?.removeEventListener('resize', onViewportResize);
  window.removeEventListener('resize', onViewportResize);
});
</script>

<template>
  <div class="app-root">
    <!-- 顶栏：标题 + 节点/应用页操作按钮 -->
    <header class="top-bar" v-if="!hideTopBar">
      <div class="top-bar-content">
        <h1 class="screen-title">{{ screenTitle }}</h1>
        <div class="top-actions" v-if="activeTab === 'nodes'">
          <md-icon-button @click="triggerNodesSettings">
            <md-icon>
              <svg viewBox="0 0 24 24">
                <path :d="topIcons.gear" />
              </svg>
            </md-icon>
          </md-icon-button>
          <md-icon-button @click="triggerNodesMenu">
            <md-icon>
              <svg viewBox="0 0 24 24">
                <path :d="topIcons.menu" />
              </svg>
            </md-icon>
          </md-icon-button>
        </div>
        <div class="top-actions" v-else-if="activeTab === 'bypass'">
          <md-icon-button @click="triggerBypassMenu">
            <md-icon>
              <svg viewBox="0 0 24 24">
                <path :d="topIcons.menu" />
              </svg>
            </md-icon>
          </md-icon-button>
        </div>
      </div>
    </header>

    <!-- 主内容区：router-view + keep-alive 缓存主页面 -->
    <main class="main-content" :style="{ height: mainHeight }">
      <div class="page-scroller">
        <router-view v-slot="{ Component }">
          <keep-alive include="DashboardScreen,NodesScreen,AppsScreen,SettingsLayout">
            <component :is="Component" :ref="setComponentRef" @navigate="handleTabChange" />
          </keep-alive>
        </router-view>
      </div>
    </main>

    <!-- 底部 tab 导航 -->
    <nav class="bottom-nav" v-if="!hideBottomNav">
      <!-- 仪表盘 -->
      <button 
        :class="['nav-tab', activeTab === 'dashboard' ? 'active' : '']"
        @click="handleTabChange('dashboard')"
        type="button">
        <div class="icon-container">
          <md-icon>
            <svg viewBox="0 0 24 24">
              <path :d="activeTab === 'dashboard' ? icons.dashboard.filled : icons.dashboard.regular" />
            </svg>
          </md-icon>
        </div>
        <span class="label">{{ t('nav.dashboard') }}</span>
      </button>

      <!-- 节点 -->
      <button 
        :class="['nav-tab', activeTab === 'nodes' ? 'active' : '']"
        @click="handleTabChange('nodes')"
        type="button">
        <div class="icon-container">
          <md-icon>
            <svg viewBox="0 0 24 24">
              <path :d="activeTab === 'nodes' ? icons.nodes.filled : icons.nodes.regular" />
            </svg>
          </md-icon>
        </div>
        <span class="label">{{ t('nav.nodes') }}</span>
      </button>

      <!-- 应用 -->
      <button 
        :class="['nav-tab', activeTab === 'bypass' ? 'active' : '']"
        @click="handleTabChange('bypass')"
        type="button">
        <div class="icon-container">
          <md-icon>
            <svg viewBox="0 0 24 24">
              <path :d="activeTab === 'bypass' ? icons.bypass.filled : icons.bypass.regular" />
            </svg>
          </md-icon>
        </div>
        <span class="label">{{ t('nav.apps') }}</span>
      </button>

      <!-- 设置 -->
      <button 
        :class="['nav-tab', activeTab === 'config' ? 'active' : '']"
        @click="handleTabChange('config')"
        type="button">
        <div class="icon-container">
          <md-icon>
            <svg viewBox="0 0 24 24">
              <path :d="activeTab === 'config' ? icons.config.filled : icons.config.regular" />
            </svg>
          </md-icon>
        </div>
        <span class="label">{{ t('nav.settings') }}</span>
      </button>
    </nav>
  </div>
</template>

<style scoped>
/* 顶栏样式 */
.top-bar {
  flex-shrink: 0;
  color: var(--md-sys-color-on-surface);
  height: calc(64px + var(--top-inset));
  padding-top: var(--top-inset);
  position: relative;
  z-index: 20;
  display: flex;
  align-items: center;
  overflow: visible;
  background-color: var(--md-sys-color-background);
}

.top-bar-content {
  height: 100%;
  width: 100%;
  padding: 20px;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  position: relative;
  user-select: none;
}

.screen-title {
  flex-grow: 1;
  margin: 0;
  font-size: 22px;
  transform-origin: left bottom;
  white-space: nowrap;
}

.top-actions {
  display: flex;
  align-items: center;
  gap: 4px;
}

/* 底部导航样式 */
.bottom-nav {
  position: fixed;
  width: 100%;
  bottom: 0;
  display: flex;
  background-color: var(--md-sys-color-surface-container-high);
  height: calc(var(--bottom-nav-height) + var(--bottom-inset));
  align-items: center;
  box-sizing: border-box;
  padding-bottom: var(--bottom-inset);
  z-index: 100;
}

.nav-tab {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2px;
  font-size: 11px;
  font-weight: 500;
  color: var(--md-sys-color-on-surface-variant);
  background: transparent;
  border: none;
  padding: 0;
  position: relative;
  overflow: hidden;
  height: 100%;
}

.icon-container {
  width: 32px;
  height: 32px;
  border-radius: var(--radius-xl);
  display: flex;
  align-items: center;
  justify-content: center;
  transition:
    width 0.2s ease,
    background-color 0.2s ease;
  pointer-events: none;
}

md-icon {
  display: flex;
  align-items: center;
  justify-content: center;
}

md-icon svg {
  width: 22px;
  height: 22px;
  fill: currentColor;
  transition:
    fill 0.2s,
    transform 0.2s;
}

.nav-tab.active .icon-container {
  background-color: var(--md-sys-color-secondary-container);
  width: 56px;
}

.nav-tab.active {
  color: var(--md-sys-color-on-surface);
}

.nav-tab.active md-icon svg {
  fill: var(--md-sys-color-on-secondary-container);
}

.nav-tab.active .label {
  font-weight: 600;
}

.label {
  transition: font-weight 0.2s;
}
</style>
