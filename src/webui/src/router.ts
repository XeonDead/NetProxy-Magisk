/**
 * @file router.ts
 * @description vue-router 路由表：底部四个主 tab（仪表盘/节点/应用/设置）+ 设置下的嵌套子页。
 *   采用 hash history 作为唯一历史真源，配合 KernelSU 的 canGoBack/goBack 驱动系统返回。
 */
import { createRouter, createWebHashHistory } from 'vue-router';

// 路由级懒加载：各页面按需分包，缩小首屏体积
const Dashboard = () => import('./components/DashboardScreen.vue');
const Nodes = () => import('./components/NodesScreen.vue');
const Bypass = () => import('./components/AppsScreen.vue');
const SettingsLayout = () => import('./components/SettingsLayout.vue');
const SettingsMain = () => import('./components/SettingsMain.vue');
const ProxySettings = () => import('./components/ProxySettingsScreen.vue');
const LogsSettings = () => import('./components/LogsScreen.vue');
const AboutSettings = () => import('./components/AboutScreen.vue');

// 路由表：根重定向到仪表盘；/settings 为布局容器，其下嵌套子页（meta.showBack 控制子页顶栏返回箭头）
const routes = [
  { path: '/', redirect: '/dashboard' },
  { path: '/dashboard', name: 'dashboard', component: Dashboard, meta: { title: '仪表盘' } },
  { path: '/nodes', name: 'nodes', component: Nodes, meta: { title: '节点' } },
  { path: '/bypass', name: 'bypass', component: Bypass, meta: { title: '应用' } },
  {
    path: '/settings',
    component: SettingsLayout,
    children: [
      { path: '', name: 'settings-main', component: SettingsMain, meta: { title: '设置' } },
      { path: 'proxy', name: 'settings-proxy', component: ProxySettings, meta: { title: '代理设置', showBack: true } },
      { path: 'logs', name: 'settings-logs', component: LogsSettings, meta: { title: '运行日志', showBack: true } },
      { path: 'about', name: 'settings-about', component: AboutSettings, meta: { title: '关于', showBack: true } }
    ]
  }
];

// 使用 hash history：作为唯一的历史真源，由 KernelSU 的 canGoBack/goBack 驱动返回。
export const router = createRouter({
  history: createWebHashHistory(),
  routes
});

