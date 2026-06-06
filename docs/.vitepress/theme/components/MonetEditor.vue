<template>
  <div class="monet-editor-container">
    <!-- 主工作区 -->
    <div class="monet-workspace">
      
      <!-- 左侧预览区 -->
      <div class="preview-panel">
        <h3 class="panel-title">效果预览</h3>
        
        <!-- 背景切换按钮组 -->
        <div class="bg-selector">
          <button 
            v-for="bg in backgrounds" 
            :key="bg.id"
            :class="['bg-btn', { active: bgType === bg.id }]"
            @click="bgType = bg.id"
            :title="bg.name"
          >
            <span class="bg-indicator" :style="bg.style"></span>
            {{ bg.name }}
          </button>
        </div>

        <!-- SVG 预览画布 -->
        <div :class="['canvas-wrapper', bgType]">
          <div class="svg-container">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" width="100%" height="100%" class="logo-preview-svg">
              <defs>
                <linearGradient id="diagGradEditor" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" :stop-color="gradStart" />
                  <stop offset="35%" :stop-color="gradStop2" />
                  <stop offset="65%" :stop-color="gradStop3" />
                  <stop offset="100%" :stop-color="gradEnd" />
                </linearGradient>
              </defs>

              <!-- 左侧竖线 -->
              <line x1="100" y1="80" x2="100" y2="320" :stroke="leftColor" :stroke-width="strokeWidth" :stroke-linecap="strokeLinecap" />

              <!-- 右侧竖线 -->
              <line x1="300" y1="80" x2="300" y2="320" :stroke="rightColor" :stroke-width="strokeWidth" :stroke-linecap="strokeLinecap" />

              <!-- 对角斜线 -->
              <line x1="100" y1="80" x2="300" y2="320" stroke="url(#diagGradEditor)" :stroke-width="strokeWidth" :stroke-linecap="strokeLinecap" :opacity="opacity" />
            </svg>
          </div>
        </div>

        <!-- 快速预设配色 -->
        <div class="presets-section">
          <h4 class="section-title">内置预设方案</h4>
          <div class="presets-grid">
            <button 
              v-for="preset in presets" 
              :key="preset.name"
              class="preset-card"
              @click="applyPreset(preset)"
            >
              <div class="preset-preview">
                <span :style="{ backgroundColor: preset.leftColor }"></span>
                <span :style="{ background: `linear-gradient(135deg, ${preset.gradStart}, ${preset.gradEnd})` }"></span>
                <span :style="{ backgroundColor: preset.rightColor }"></span>
              </div>
              <span class="preset-name">{{ preset.name }}</span>
            </button>
          </div>
        </div>
      </div>

      <!-- 右侧控制区 -->
      <div class="control-panel">
        <h3 class="panel-title">调色与设计参数</h3>

        <!-- Monet 种子取色 -->
        <div class="control-group">
          <div class="group-header">
            <h4>Monet 自动配色引擎</h4>
            <span class="tooltip">选择种子颜色，自动推导调和配色</span>
          </div>
          <div class="seed-picker-wrapper">
            <div class="color-picker-input">
              <input type="color" v-model="seedColor" @input="onSeedColorChange" />
              <input type="text" v-model="seedColor" @input="onSeedColorChange" class="hex-text-input" placeholder="#003BCC" />
            </div>
            <button class="action-btn-secondary" @click="randomizeSeed">随机种子</button>
          </div>
        </div>

        <!-- 手动调色细化 -->
        <div class="control-group">
          <div class="group-header">
            <h4>手动细节微调</h4>
            <label class="auto-calc-toggle">
              <input type="checkbox" v-model="autoGenerate" />
              <span>绑定 Monet 引擎</span>
            </label>
          </div>

          <div class="fine-tune-grid">
            <div class="tune-item">
              <span class="tune-label">左侧线条</span>
              <div class="color-picker-input compact">
                <input type="color" v-model="leftColor" @input="autoGenerate = false" />
                <input type="text" v-model="leftColor" @input="autoGenerate = false" class="hex-text-input" />
              </div>
            </div>

            <div class="tune-item">
              <span class="tune-label">右侧线条</span>
              <div class="color-picker-input compact">
                <input type="color" v-model="rightColor" @input="autoGenerate = false" />
                <input type="text" v-model="rightColor" @input="autoGenerate = false" class="hex-text-input" />
              </div>
            </div>

            <div class="tune-item full-width">
              <span class="tune-label">对角渐变 Stop 1 (0%)</span>
              <div class="color-picker-input compact">
                <input type="color" v-model="gradStart" @input="autoGenerate = false" />
                <input type="text" v-model="gradStart" @input="autoGenerate = false" class="hex-text-input" />
              </div>
            </div>

            <div class="tune-item full-width">
              <span class="tune-label">对角渐变 Stop 2 (35%)</span>
              <div class="color-picker-input compact">
                <input type="color" v-model="gradStop2" @input="autoGenerate = false" />
                <input type="text" v-model="gradStop2" @input="autoGenerate = false" class="hex-text-input" />
              </div>
            </div>

            <div class="tune-item full-width">
              <span class="tune-label">对角渐变 Stop 3 (65%)</span>
              <div class="color-picker-input compact">
                <input type="color" v-model="gradStop3" @input="autoGenerate = false" />
                <input type="text" v-model="gradStop3" @input="autoGenerate = false" class="hex-text-input" />
              </div>
            </div>

            <div class="tune-item full-width">
              <span class="tune-label">对角渐变 Stop 4 (100%)</span>
              <div class="color-picker-input compact">
                <input type="color" v-model="gradEnd" @input="autoGenerate = false" />
                <input type="text" v-model="gradEnd" @input="autoGenerate = false" class="hex-text-input" />
              </div>
            </div>
          </div>
        </div>

        <!-- 几何与特效参数 -->
        <div class="control-group">
          <h4>几何与布局参数</h4>
          <div class="settings-sliders">
            <div class="slider-item">
              <div class="slider-header">
                <span>线条粗细 (Stroke Width)</span>
                <span class="value-badge">{{ strokeWidth }}px</span>
              </div>
              <input type="range" min="40" max="130" step="1" v-model.number="strokeWidth" />
            </div>

            <div class="slider-item">
              <div class="slider-header">
                <span>对角线透明度 (Opacity)</span>
                <span class="value-badge">{{ opacity }}</span>
              </div>
              <input type="range" min="0.1" max="1" step="0.05" v-model.number="opacity" />
            </div>

            <div class="slider-item">
              <div class="slider-header">
                <span>线帽样式 (Stroke Cap)</span>
              </div>
              <div class="radio-group">
                <button 
                  v-for="cap in ['round', 'butt', 'square']" 
                  :key="cap"
                  :class="['radio-btn', { active: strokeLinecap === cap }]"
                  @click="strokeLinecap = cap"
                >
                  {{ cap }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 底部导出板块 -->
    <div class="export-panel">
      <div class="export-tabs-header">
        <button 
          :class="['tab-btn', { active: activeTab === 'svg' }]" 
          @click="activeTab = 'svg'"
        >
          SVG 源码
        </button>
        <button 
          :class="['tab-btn', { active: activeTab === 'vector' }]" 
          @click="activeTab = 'vector'"
        >
          Android Vector Drawable (XML)
        </button>
      </div>

      <div class="export-tab-content">
        <!-- SVG Code Tab -->
        <div v-show="activeTab === 'svg'" class="code-container">
          <pre class="code-block"><code>{{ generatedSVG }}</code></pre>
          <div class="code-actions">
            <button class="action-btn" @click="copySVGCode">
              {{ copyTextSVG }}
            </button>
            <button class="action-btn btn-success" @click="downloadSVGFile">
              下载 SVG
            </button>
          </div>
        </div>

        <!-- Android Vector Tab -->
        <div v-show="activeTab === 'vector'" class="code-container">
          <pre class="code-block"><code>{{ generatedVector }}</code></pre>
          <div class="code-actions">
            <button class="action-btn" @click="copyVectorCode">
              {{ copyTextVector }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'

// 响应式设计变量
const seedColor = ref('#003BCC')
const leftColor = ref('#0DD8F5')
const rightColor = ref('#79F5A9')
const gradStart = ref('#003BCC')
const gradStop2 = ref('#28CBE6')
const gradStop3 = ref('#55E6AA')
const gradEnd = ref('#004A8F')

const strokeWidth = ref(88)
const opacity = ref(0.85)
const strokeLinecap = ref('round')

const bgType = ref('checkerboard')
const activeTab = ref('svg')
const autoGenerate = ref(true)

const copyTextSVG = ref('复制 SVG 代码')
const copyTextVector = ref('复制 Vector XML')

// 背景配置列表
const backgrounds = [
  { id: 'checkerboard', name: '透明棋盘', style: { backgroundImage: 'linear-gradient(45deg, #bbb 25%, transparent 25%, transparent 75%, #bbb 75%), linear-gradient(45deg, #bbb 25%, #eee 25%, #eee 75%, #bbb 75%)', backgroundSize: '8px 8px', backgroundPosition: '0 0, 4px 4px' } },
  { id: 'dark', name: '深色背景', style: { backgroundColor: '#1A1A1E' } },
  { id: 'light', name: '浅色背景', style: { backgroundColor: '#FFFFFF', border: '1px solid #ddd' } },
  { id: 'grad-dark', name: '深色渐变', style: { background: 'linear-gradient(135deg, #1f1f2e, #0f0f15)' } },
  { id: 'grad-light', name: '浅色渐变', style: { background: 'linear-gradient(135deg, #eef2f3, #8e9eab)' } }
]

// 内置预设方案
const presets = [
  {
    name: 'NetProxy 原版',
    seedColor: '#003BCC',
    leftColor: '#0DD8F5',
    rightColor: '#79F5A9',
    gradStart: '#003BCC',
    gradStop2: '#28CBE6',
    gradStop3: '#55E6AA',
    gradEnd: '#004A8F'
  },
  {
    name: '莫奈薰衣草',
    seedColor: '#6750A4',
    leftColor: '#D0BCFF',
    rightColor: '#EFB8C8',
    gradStart: '#4F378B',
    gradStop2: '#6750A4',
    gradStop3: '#9A82DB',
    gradEnd: '#381E72'
  },
  {
    name: '莫奈夏日薄荷',
    seedColor: '#059669',
    leftColor: '#A7F3D0',
    rightColor: '#FDE047',
    gradStart: '#064E3B',
    gradStop2: '#059669',
    gradStop3: '#34D399',
    gradEnd: '#022C22'
  },
  {
    name: '莫奈皇家沙菲尔',
    seedColor: '#1D4ED8',
    leftColor: '#93C5FD',
    rightColor: '#C084FC',
    gradStart: '#1E3A8A',
    gradStop2: '#2563EB',
    gradStop3: '#60A5FA',
    gradEnd: '#172554'
  },
  {
    name: '莫奈浅粉樱花',
    seedColor: '#DB2777',
    leftColor: '#FBCFE8',
    rightColor: '#FCA5A5',
    gradStart: '#881337',
    gradStop2: '#DB2777',
    gradStop3: '#F472B6',
    gradEnd: '#4C0519'
  },
  {
    name: '莫奈秋日暖枫',
    seedColor: '#D97706',
    leftColor: '#FDE68A',
    rightColor: '#FCA5A5',
    gradStart: '#78350F',
    gradStop2: '#D97706',
    gradStop3: '#FBBF24',
    gradEnd: '#451A03'
  }
]

// 颜色模型辅助算法 (Hex <-> HSL)
function hexToHsl(hex) {
  hex = hex.replace(/^#/, '')
  if (hex.length === 3) {
    hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2]
  }
  let r = parseInt(hex.substring(0, 2), 16) / 255
  let g = parseInt(hex.substring(2, 4), 16) / 255
  let b = parseInt(hex.substring(4, 6), 16) / 255

  let max = Math.max(r, g, b), min = Math.min(r, g, b)
  let h, s, l = (max + min) / 2

  if (max === min) {
    h = s = 0
  } else {
    let d = max - min
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    switch (max) {
      case r: h = (g - b) / d + (g < b ? 6 : 0); break
      case g: h = (b - r) / d + 2; break
      case b: h = (r - g) / d + 4; break
    }
    h /= 6
  }

  return {
    h: Math.round(h * 360),
    s: Math.round(s * 100),
    l: Math.round(l * 100)
  }
}

function hslToHex(h, s, l) {
  h /= 360
  s /= 100
  l /= 100
  let r, g, b

  if (s === 0) {
    r = g = b = l
  } else {
    const hue2rgb = (p, q, t) => {
      if (t < 0) t += 1
      if (t > 1) t -= 1
      if (t < 1/6) return p + (q - p) * 6 * t
      if (t < 1/2) return q
      if (t < 2/3) return p + (q - p) * (2/3 - t) * 6
      return p
    }
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    r = hue2rgb(p, q, h + 1/3)
    g = hue2rgb(p, q, h)
    b = hue2rgb(p, q, h - 1/3)
  }

  const toHex = x => {
    const val = Math.round(x * 255).toString(16)
    return val.length === 1 ? '0' + val : val
  }
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`
}

// 基于主种子颜色生成一整套和谐的莫奈取色方案
const calculateMonetScheme = (seed) => {
  if (!/^#[0-9A-F]{6}$/i.test(seed)) return
  
  const { h, s, l } = hexToHsl(seed)
  
  // 1. 左侧竖线：使用色相逆时针偏移 Analogous 辅助调，稍微提亮
  leftColor.value = hslToHex((h - 32 + 360) % 360, Math.min(s + 10, 95), Math.max(l, 58))
  
  // 2. 右侧竖线：使用色相顺时针偏移 Analogous 辅助调，更亮更柔和
  rightColor.value = hslToHex((h + 38) % 360, Math.min(s + 5, 90), Math.max(l + 10, 68))
  
  // 3. 对角斜线：使用带渐变的莫奈色系覆盖
  gradStart.value = hslToHex(h, Math.max(s, 75), Math.max(l - 18, 25))
  gradStop2.value = hslToHex((h + 8) % 360, Math.max(s, 70), Math.max(l - 5, 45))
  gradStop3.value = hslToHex((h + 24) % 360, Math.max(s - 10, 60), Math.min(l + 12, 75))
  gradEnd.value = hslToHex((h - 15 + 360) % 360, Math.max(s, 80), Math.max(l - 25, 20))
}

const onSeedColorChange = () => {
  autoGenerate.value = true
  calculateMonetScheme(seedColor.value)
}

const randomizeSeed = () => {
  const randomColor = '#' + Math.floor(Math.random()*16777215).toString(16).padStart(6, '0').toUpperCase()
  seedColor.value = randomColor
  autoGenerate.value = true
  calculateMonetScheme(randomColor)
}

const applyPreset = (preset) => {
  autoGenerate.value = false
  seedColor.value = preset.seedColor
  leftColor.value = preset.leftColor
  rightColor.value = preset.rightColor
  gradStart.value = preset.gradStart
  gradStop2.value = preset.gradStop2
  gradStop3.value = preset.gradStop3
  gradEnd.value = preset.gradEnd
}

// 自动生成代码块
const generatedSVG = computed(() => {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" width="100%" height="100%">
  <defs>
    <linearGradient id="diagGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${gradStart.value}" />
      <stop offset="35%" stop-color="${gradStop2.value}" />
      <stop offset="65%" stop-color="${gradStop3.value}" />
      <stop offset="100%" stop-color="${gradEnd.value}" />
    </linearGradient>
  </defs>

  <line x1="100" y1="80" x2="100" y2="320" stroke="${leftColor.value}" stroke-width="${strokeWidth.value}" stroke-linecap="${strokeLinecap.value}" />

  <line x1="300" y1="80" x2="300" y2="320" stroke="${rightColor.value}" stroke-width="${strokeWidth.value}" stroke-linecap="${strokeLinecap.value}" />

  <line x1="100" y1="80" x2="300" y2="320" stroke="url(#diagGrad)" stroke-width="${strokeWidth.value}" stroke-linecap="${strokeLinecap.value}" opacity="${opacity.value}" />
</svg>`
})

const generatedVector = computed(() => {
  return `<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="400dp"
    android:height="400dp"
    android:viewportWidth="400"
    android:viewportHeight="400">

    <!-- 左侧竖线 -->
    <path
        android:pathData="M 100,80 L 100,320"
        android:strokeColor="${leftColor.value}"
        android:strokeWidth="${strokeWidth.value}"
        android:strokeLineCap="${strokeLinecap.value}" />

    <!-- 右侧竖线 -->
    <path
        android:pathData="M 300,80 L 300,320"
        android:strokeColor="${rightColor.value}"
        android:strokeWidth="${strokeWidth.value}"
        android:strokeLineCap="${strokeLinecap.value}" />

    <!-- 对角斜线 (使用渐变) -->
    <path
        android:pathData="M 100,80 L 300,320"
        android:strokeWidth="${strokeWidth.value}"
        android:strokeLineCap="${strokeLinecap.value}"
        android:strokeAlpha="${opacity.value}">
        <aapt:attr name="android:strokeColor">
            <gradient
                android:startX="100"
                android:startY="80"
                android:endX="300"
                android:endY="320"
                android:type="linear">
                <item android:offset="0.0" android:color="${gradStart.value}" />
                <item android:offset="0.35" android:color="${gradStop2.value}" />
                <item android:offset="0.65" android:color="${gradStop3.value}" />
                <item android:offset="1.0" android:color="${gradEnd.value}" />
            </gradient>
        </aapt:attr>
    </path>
</vector>`
})

// 复制及下载操作
const copySVGCode = async () => {
  try {
    await navigator.clipboard.writeText(generatedSVG.value)
    copyTextSVG.value = '已复制 SVG 源码！'
    setTimeout(() => {
      copyTextSVG.value = '复制 SVG 代码'
    }, 2000)
  } catch (err) {
    copyTextSVG.value = '复制失败'
  }
}

const copyVectorCode = async () => {
  try {
    await navigator.clipboard.writeText(generatedVector.value)
    copyTextVector.value = '已复制 Vector XML！'
    setTimeout(() => {
      copyTextVector.value = '复制 Vector XML'
    }, 2000)
  } catch (err) {
    copyTextVector.value = '复制失败'
  }
}

const downloadSVGFile = () => {
  const blob = new Blob([generatedSVG.value], { type: 'image/svg+xml' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'N.svg'
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}
</script>

<style scoped>
/* 莫奈查看器样式体系 */
.monet-editor-container {
  display: flex;
  flex-direction: column;
  gap: 2rem;
  margin-top: 1.5rem;
  font-family: var(--vp-font-family-base);
}

.monet-workspace {
  display: grid;
  grid-template-columns: 1fr;
  gap: 2rem;
}

@media (min-width: 768px) {
  .monet-workspace {
    grid-template-columns: 1.2fr 1fr;
  }
}

/* 面板通用样式 */
.preview-panel,
.control-panel,
.export-panel {
  background-color: var(--vp-c-bg-soft);
  border: 1px solid var(--vp-c-gutter);
  border-radius: 16px;
  padding: 1.5rem;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.05);
  backdrop-filter: blur(12px);
  transition: all 0.3s ease;
}

.panel-title {
  margin-top: 0 !important;
  margin-bottom: 1.2rem;
  font-weight: 700;
  font-size: 1.25rem;
  border-bottom: 2px solid var(--vp-c-gutter);
  padding-bottom: 0.5rem;
  color: var(--vp-c-text-1);
}

/* 背景切换器 */
.bg-selector {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.bg-btn {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.85rem;
  padding: 0.3rem 0.6rem;
  border-radius: 8px;
  border: 1px solid var(--vp-c-gutter);
  background-color: var(--vp-c-bg);
  cursor: pointer;
  transition: all 0.2s;
  color: var(--vp-c-text-1);
}

.bg-btn.active {
  border-color: var(--vp-c-brand);
  background-color: var(--vp-c-brand-soft);
}

.bg-indicator {
  display: inline-block;
  width: 14px;
  height: 14px;
  border-radius: 4px;
}

/* 画布包装区 */
.canvas-wrapper {
  aspect-ratio: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 12px;
  overflow: hidden;
  padding: 2.5rem;
  border: 1px solid var(--vp-c-gutter);
  position: relative;
  transition: background 0.3s;
}

.canvas-wrapper.checkerboard {
  background-color: #eee;
  background-image: linear-gradient(45deg, #e0e0e0 25%, transparent 25%, transparent 75%, #e0e0e0 75%), 
                    linear-gradient(45deg, #e0e0e0 25%, #ffffff 25%, #ffffff 75%, #e0e0e0 75%);
  background-size: 16px 16px;
  background-position: 0 0, 8px 8px;
}

.canvas-wrapper.dark {
  background-color: #1A1A1E;
}

.canvas-wrapper.light {
  background-color: #FFFFFF;
}

.canvas-wrapper.grad-dark {
  background: linear-gradient(135deg, #1f1f2e, #0f0f15);
}

.canvas-wrapper.grad-light {
  background: linear-gradient(135deg, #eef2f3, #8e9eab);
}

.svg-container {
  width: 100%;
  max-width: 280px;
  filter: drop-shadow(0 8px 24px rgba(0, 0, 0, 0.15));
  transition: transform 0.3s ease;
}

.svg-container:hover {
  transform: scale(1.02);
}

/* 预设配色网格 */
.presets-section {
  margin-top: 1.5rem;
}

.section-title {
  font-size: 0.95rem;
  color: var(--vp-c-text-2);
  margin-bottom: 0.8rem;
}

.presets-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.6rem;
}

.preset-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.4rem;
  padding: 0.6rem;
  border-radius: 10px;
  border: 1px solid var(--vp-c-gutter);
  background-color: var(--vp-c-bg);
  cursor: pointer;
  transition: all 0.2s;
}

.preset-card:hover {
  border-color: var(--vp-c-brand);
  transform: translateY(-2px);
}

.preset-preview {
  display: flex;
  width: 100%;
  height: 24px;
  border-radius: 6px;
  overflow: hidden;
  border: 1px solid var(--vp-c-gutter);
}

.preset-preview span {
  flex: 1;
}

.preset-name {
  font-size: 0.75rem;
  text-align: center;
  color: var(--vp-c-text-1);
}

/* 控制台设置项 */
.control-group {
  margin-bottom: 1.5rem;
  border-bottom: 1px dashed var(--vp-c-gutter);
  padding-bottom: 1.2rem;
}

.control-group:last-child {
  margin-bottom: 0;
  border-bottom: none;
  padding-bottom: 0;
}

.control-group h4 {
  margin-top: 0 !important;
  margin-bottom: 0.6rem;
  font-size: 1rem;
  color: var(--vp-c-text-1);
  font-weight: 600;
}

.group-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.8rem;
}

.group-header h4 {
  margin-bottom: 0 !important;
}

.tooltip {
  font-size: 0.75rem;
  color: var(--vp-c-text-3);
}

.auto-calc-toggle {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.8rem;
  color: var(--vp-c-text-2);
  cursor: pointer;
}

/* 种子选择器 */
.seed-picker-wrapper {
  display: flex;
  gap: 0.8rem;
}

.color-picker-input {
  display: flex;
  align-items: center;
  border: 1px solid var(--vp-c-gutter);
  border-radius: 8px;
  background-color: var(--vp-c-bg);
  padding: 0.25rem 0.5rem;
  flex-grow: 1;
}

.color-picker-input input[type="color"] {
  border: none;
  width: 28px;
  height: 28px;
  padding: 0;
  background: none;
  cursor: pointer;
  margin-right: 0.5rem;
  border-radius: 4px;
}

.hex-text-input {
  border: none;
  background: none;
  outline: none;
  font-family: var(--vp-font-family-mono);
  font-size: 0.9rem;
  color: var(--vp-c-text-1);
  width: 100%;
}

/* 手动细调网格 */
.fine-tune-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 0.8rem;
}

.tune-item {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}

.tune-item.full-width {
  grid-column: span 2;
}

.tune-label {
  font-size: 0.8rem;
  color: var(--vp-c-text-2);
}

.color-picker-input.compact {
  padding: 0.15rem 0.4rem;
}

.color-picker-input.compact input[type="color"] {
  width: 22px;
  height: 22px;
}

/* 滑块设置与收音单选 */
.settings-sliders {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.slider-item {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}

.slider-header {
  display: flex;
  justify-content: space-between;
  font-size: 0.85rem;
  color: var(--vp-c-text-2);
}

.value-badge {
  font-family: var(--vp-font-family-mono);
  background-color: var(--vp-c-brand-soft);
  color: var(--vp-c-brand);
  padding: 0.05rem 0.3rem;
  border-radius: 4px;
  font-size: 0.75rem;
}

input[type="range"] {
  width: 100%;
  accent-color: var(--vp-c-brand);
}

.radio-group {
  display: flex;
  gap: 0.5rem;
  background-color: var(--vp-c-bg);
  border: 1px solid var(--vp-c-gutter);
  padding: 0.2rem;
  border-radius: 8px;
}

.radio-btn {
  flex: 1;
  font-size: 0.8rem;
  padding: 0.3rem;
  border-radius: 6px;
  border: none;
  background: none;
  color: var(--vp-c-text-2);
  cursor: pointer;
  transition: all 0.2s;
}

.radio-btn.active {
  background-color: var(--vp-c-brand);
  color: var(--vp-c-bg);
  font-weight: 600;
}

/* 导出面板与代码块 */
.export-panel {
  display: flex;
  flex-direction: column;
}

.export-tabs-header {
  display: flex;
  gap: 0.5rem;
  border-bottom: 2px solid var(--vp-c-gutter);
  margin-bottom: 1rem;
}

.tab-btn {
  padding: 0.5rem 1rem;
  font-size: 0.9rem;
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  margin-bottom: -2px;
  color: var(--vp-c-text-2);
  cursor: pointer;
  transition: all 0.2s;
}

.tab-btn.active {
  color: var(--vp-c-brand);
  border-bottom-color: var(--vp-c-brand);
  font-weight: 600;
}

.code-container {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.code-block {
  margin: 0 !important;
  background-color: var(--vp-c-bg) !important;
  border: 1px solid var(--vp-c-gutter);
  border-radius: 8px;
  padding: 1rem;
  max-height: 250px;
  overflow: auto;
  font-family: var(--vp-font-family-mono);
  font-size: 0.85rem;
  white-space: pre-wrap;
  word-break: break-all;
}

.code-block code {
  color: var(--vp-c-text-1) !important;
  background: none !important;
  padding: 0 !important;
}

.code-actions {
  display: flex;
  gap: 0.8rem;
}

.action-btn {
  flex-grow: 1;
  padding: 0.6rem 1.2rem;
  border-radius: 8px;
  border: 1px solid var(--vp-c-brand);
  background-color: var(--vp-c-brand);
  color: var(--vp-c-bg);
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  text-align: center;
}

.action-btn:hover {
  background-color: var(--vp-c-brand-dark);
  border-color: var(--vp-c-brand-dark);
}

.action-btn-secondary {
  padding: 0.5rem 1rem;
  border-radius: 8px;
  border: 1px solid var(--vp-c-gutter);
  background-color: var(--vp-c-bg);
  color: var(--vp-c-text-1);
  font-size: 0.85rem;
  cursor: pointer;
  transition: all 0.2s;
}

.action-btn-secondary:hover {
  border-color: var(--vp-c-brand);
  color: var(--vp-c-brand);
}

.btn-success {
  background-color: transparent;
  color: var(--vp-c-brand);
  border: 1px solid var(--vp-c-brand);
}

.btn-success:hover {
  background-color: var(--vp-c-brand-soft);
}
</style>
