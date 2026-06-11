/**
 * @file main.ts
 * @description WebUI 应用入口：创建 Vue 应用，全局注册所需的 Material Web 组件（md-*），
 *   装配路由与 i18n，最后挂载到 #app。
 */
import { createApp } from 'vue'
import './style.css'
import App from './App.vue'

// 全局注册用到的 Material Web 组件（逐个按需引入，未引入的不进包）
import '@material/web/button/filled-button.js'
import '@material/web/button/outlined-button.js'
import '@material/web/button/elevated-button.js'
import '@material/web/button/text-button.js'
import '@material/web/iconbutton/icon-button.js'
import '@material/web/switch/switch.js'
import '@material/web/slider/slider.js'
import '@material/web/tabs/tabs.js'
import '@material/web/tabs/primary-tab.js'
import '@material/web/dialog/dialog.js'
import '@material/web/list/list.js'
import '@material/web/list/list-item.js'
import '@material/web/progress/linear-progress.js'
import '@material/web/progress/circular-progress.js'
import '@material/web/textfield/outlined-text-field.js'
import '@material/web/checkbox/checkbox.js'

import { router } from './router'
import { i18n } from './i18n'

// 装配路由与 i18n 后挂载到 #app
createApp(App).use(router).use(i18n).mount('#app')


