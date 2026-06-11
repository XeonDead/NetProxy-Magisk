/**
 * @file vite.config.ts
 * @description Vite 构建配置：启用 Vue 插件并把 `md-` 前缀标签视为自定义元素（适配 @material/web），
 *   构建产物输出到上级的 src/module/webroot（即模块 WebUI 根目录）。
 */
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue({
      template: {
        compilerOptions: {
          // 把所有以 'md-' 开头的标签视为自定义元素（供 @material/web 使用）
          isCustomElement: (tag) => tag.startsWith('md-')
        }
      }
    })
  ],
  build: {
    // __dirname 即 src/webui，输出到模块目录下的 src/module/webroot（webroot 仍随模块打包）
    outDir: resolve(__dirname, '../module/webroot'),
    emptyOutDir: true
  }
})
