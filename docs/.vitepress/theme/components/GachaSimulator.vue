<template>
  <div class="gacha-game-container">
    <!-- 顶部状态与音效控制 -->
    <div class="game-header">
      <div class="crystal-display">
        <span class="crystal-icon">💎</span>
        <span class="crystal-count">{{ crystals }}</span>
      </div>
      <button class="sound-toggle" @click="toggleMute" :title="isMuted ? '取消静音' : '静音'">
        {{ isMuted ? '🔇' : '🔊' }}
      </button>
    </div>

    <!-- 游戏主舞台 -->
    <div class="game-stage">
      
      <!-- 主祈愿卡池界面 -->
      <div v-if="gameState === 'lobby'" class="banner-lobby">
        <div class="banner-card">
          <div class="banner-title-area">
            <span class="banner-tag">限时祈愿</span>
            <h2 class="banner-title">莫奈的幻想空间</h2>
            <p class="banner-desc">概率大UP！极光幻夜 & 红莲劫火 5星限定莫奈配色图标限时登场！</p>
          </div>
          <div class="featured-items">
            <!-- 5星极光幻夜微缩卡牌 -->
            <div class="featured-card aurora-mini">
              <div class="mini-svg">
                <svg viewBox="0 0 400 400" width="80" height="80">
                  <defs>
                    <linearGradient id="auroraGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                      <stop offset="0%" stop-color="#006064" />
                      <stop offset="35%" stop-color="#00838F" />
                      <stop offset="65%" stop-color="#8E24AA" />
                      <stop offset="100%" stop-color="#4A148C" />
                    </linearGradient>
                  </defs>
                  <line x1="100" y1="80" x2="100" y2="320" stroke="#80DEEA" stroke-width="88" stroke-linecap="round" />
                  <line x1="300" y1="80" x2="300" y2="320" stroke="#E1BEE7" stroke-width="88" stroke-linecap="round" />
                  <line x1="100" y1="80" x2="300" y2="320" stroke="url(#auroraGrad)" stroke-width="88" stroke-linecap="round" opacity="0.85" />
                </svg>
              </div>
              <span class="feat-name">极光幻夜</span>
              <span class="feat-stars">⭐⭐⭐⭐⭐</span>
            </div>

            <!-- 5星红莲劫火微缩卡牌 -->
            <div class="featured-card inferno-mini">
              <div class="mini-svg">
                <svg viewBox="0 0 400 400" width="80" height="80">
                  <defs>
                    <linearGradient id="infernoGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                      <stop offset="0%" stop-color="#3700B3" />
                      <stop offset="35%" stop-color="#D50000" />
                      <stop offset="65%" stop-color="#FF1744" />
                      <stop offset="100%" stop-color="#800808" />
                    </linearGradient>
                  </defs>
                  <line x1="100" y1="80" x2="100" y2="320" stroke="#FF8A80" stroke-width="88" stroke-linecap="round" />
                  <line x1="300" y1="80" x2="300" y2="320" stroke="#FF5252" stroke-width="88" stroke-linecap="round" />
                  <line x1="100" y1="80" x2="300" y2="320" stroke="url(#infernoGrad)" stroke-width="88" stroke-linecap="round" opacity="0.85" />
                </svg>
              </div>
              <span class="feat-name">红莲劫火</span>
              <span class="feat-stars">⭐⭐⭐⭐⭐</span>
            </div>
          </div>
        </div>

        <!-- 祈愿按钮组 -->
        <div class="gacha-actions">
          <button class="gacha-btn single-pull" @click="performWish(1)">
            <span class="btn-text">祈愿 1 次</span>
            <span class="btn-cost">💎 160</span>
          </button>
          <button class="gacha-btn ten-pull" @click="performWish(10)">
            <span class="btn-text">祈愿 10 次</span>
            <span class="btn-cost">💎 1600</span>
          </button>
        </div>

        <div class="pity-counter">
          已累计 <strong>{{ pity5StarCount }}</strong> 抽未出 5 星（80 抽必定保底，10 抽必定保底 4 星）
        </div>
      </div>

      <!-- 祈愿大屏图层（包含流星动画和结果展示，均共享全屏星空夜空背景） -->
      <div v-else class="gacha-wish-overlay">
        <!-- 背景星空粒子 -->
        <div class="stars-particle-bg"></div>
        <div class="nebula-glow"></div>

        <!-- 1. 流星动画状态 -->
        <div v-if="gameState === 'animation'" class="animation-stage-inner" @click="skipAnimation">
          <div class="skip-tip">点击任意处跳过动画</div>
          <div :class="['meteor-trail', highestRarityClass]"></div>
        </div>

        <!-- 2. 单次抽取展示界面 -->
        <div v-if="gameState === 'single-reveal'" class="reveal-stage single">
          <div class="card-display-container">
            <div :class="['card-frame', getRarityClass(revealList[0].rarity)]">
              <div class="card-glow"></div>
              <div class="card-inner">
                <div class="card-header-info">
                  <span class="card-stars">{{ '⭐'.repeat(revealList[0].rarity) }}</span>
                  <span class="card-rarity-text">{{ revealList[0].rarity }}星限定配色</span>
                </div>
                <div class="card-svg-view">
                  <svg viewBox="0 0 400 400" width="100%" height="100%">
                    <defs>
                      <linearGradient :id="'singleGrad' + revealList[0].id" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" :stop-color="revealList[0].colors.gradStart" />
                        <stop offset="35%" :stop-color="revealList[0].colors.gradStop2" />
                        <stop offset="65%" :stop-color="revealList[0].colors.gradStop3" />
                        <stop offset="100%" :stop-color="revealList[0].colors.gradEnd" />
                      </linearGradient>
                    </defs>
                    <line x1="100" y1="80" x2="100" y2="320" :stroke="revealList[0].colors.leftColor" stroke-width="88" stroke-linecap="round" />
                    <line x1="300" y1="80" x2="300" y2="320" :stroke="revealList[0].colors.rightColor" stroke-width="88" stroke-linecap="round" />
                    <line x1="100" y1="80" x2="300" y2="320" :stroke="'url(#singleGrad' + revealList[0].id + ')'" stroke-width="88" stroke-linecap="round" opacity="0.85" />
                  </svg>
                </div>
                <div class="card-footer-info">
                  <h3 class="card-title">{{ revealList[0].name }}</h3>
                  <p class="card-desc">{{ revealList[0].desc }}</p>
                </div>
              </div>
            </div>
          </div>

          <div class="reveal-actions">
            <button class="action-btn" @click="copyRevealCode(revealList[0], 'svg')">
              {{ copyBtnText }}
            </button>
            <button class="action-btn btn-secondary" @click="copyRevealCode(revealList[0], 'vector')">
              {{ copyBtnTextVector }}
            </button>
            <button class="action-btn btn-confirm" @click="closeReveal">确定</button>
          </div>
        </div>

        <!-- 3. 十连抽展示界面 -->
        <div v-if="gameState === 'ten-reveal'" class="reveal-stage ten">
          <h3 class="ten-reveal-title">祈愿结果</h3>
          <div class="ten-grid">
            <div 
              v-for="(item, idx) in revealList" 
              :key="idx" 
              :class="['grid-card', getRarityClass(item.rarity)]"
              @click="selectDetailCard(item)"
            >
              <div class="grid-card-svg">
                <svg viewBox="0 0 400 400" width="60" height="60">
                  <defs>
                    <linearGradient :id="'tenGrad' + idx" x1="0%" y1="0%" x2="100%" y2="100%">
                      <stop offset="0%" :stop-color="item.colors.gradStart" />
                      <stop offset="35%" :stop-color="item.colors.gradStop2" />
                      <stop offset="65%" :stop-color="item.colors.gradStop3" />
                      <stop offset="100%" :stop-color="item.colors.gradEnd" />
                    </linearGradient>
                  </defs>
                  <line x1="100" y1="80" x2="100" y2="320" :stroke="item.colors.leftColor" stroke-width="88" stroke-linecap="round" />
                  <line x1="300" y1="80" x2="300" y2="320" :stroke="item.colors.rightColor" stroke-width="88" stroke-linecap="round" />
                  <line x1="100" y1="80" x2="300" y2="320" :stroke="'url(#tenGrad' + idx + ')'" stroke-width="88" stroke-linecap="round" opacity="0.85" />
                </svg>
              </div>
              <div class="grid-card-info">
                <span class="grid-card-name">{{ item.name }}</span>
                <span class="grid-card-stars">{{ '★'.repeat(item.rarity) }}</span>
              </div>
            </div>
          </div>

          <!-- 详细查看与复制代码模态框 -->
          <div v-if="detailCard" class="modal-overlay" @click.self="detailCard = null">
            <div class="modal-content">
              <div class="modal-card-display">
                <div :class="['card-frame compact', getRarityClass(detailCard.rarity)]">
                  <div class="card-inner">
                    <div class="card-svg-view">
                      <svg viewBox="0 0 400 400" width="160" height="160">
                        <defs>
                          <linearGradient id="modalGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                            <stop offset="0%" :stop-color="detailCard.colors.gradStart" />
                            <stop offset="35%" :stop-color="detailCard.colors.gradStop2" />
                            <stop offset="65%" :stop-color="detailCard.colors.gradStop3" />
                            <stop offset="100%" :stop-color="detailCard.colors.gradEnd" />
                          </linearGradient>
                        </defs>
                        <line x1="100" y1="80" x2="100" y2="320" :stroke="detailCard.colors.leftColor" stroke-width="88" stroke-linecap="round" />
                        <line x1="300" y1="80" x2="300" y2="320" :stroke="detailCard.colors.rightColor" stroke-width="88" stroke-linecap="round" />
                        <line x1="100" y1="80" x2="300" y2="320" stroke="url(#modalGrad)" stroke-width="88" stroke-linecap="round" opacity="0.85" />
                      </svg>
                    </div>
                    <h4 class="card-title">{{ detailCard.name }}</h4>
                    <p class="card-desc">{{ detailCard.desc }}</p>
                  </div>
                </div>
              </div>
              <div class="modal-actions">
                <button class="action-btn" @click="copyRevealCode(detailCard, 'svg')">
                  {{ copyBtnText }}
                </button>
                <button class="action-btn btn-secondary" @click="copyRevealCode(detailCard, 'vector')">
                  {{ copyBtnTextVector }}
                </button>
                <button class="action-btn btn-confirm" @click="detailCard = null">关闭</button>
              </div>
            </div>
          </div>

          <div class="reveal-actions">
            <button class="action-btn btn-confirm" @click="closeReveal">确定</button>
          </div>
        </div>
      </div>
    </div>

    <!-- 祈愿图鉴 (Collection) -->
    <div class="collection-section">
      <h3 class="panel-title">我的色彩收藏 (已解锁 {{ unlockedList.length }} 种配色)</h3>
      <div v-if="unlockedList.length === 0" class="empty-collection">
        您尚未进行祈愿，快去上方抽取您的莫奈色卡吧！
      </div>
      <div v-else class="collection-grid">
        <div 
          v-for="(item, idx) in unlockedList" 
          :key="idx" 
          :class="['collection-item', getRarityClass(item.rarity)]"
          @click="selectDetailCard(item)"
        >
          <div class="collection-svg">
            <svg viewBox="0 0 400 400" width="40" height="40">
              <defs>
                <linearGradient :id="'collGrad' + idx" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" :stop-color="item.colors.gradStart" />
                  <stop offset="35%" :stop-color="item.colors.gradStop2" />
                  <stop offset="65%" :stop-color="item.colors.gradStop3" />
                  <stop offset="100%" :stop-color="item.colors.gradEnd" />
                </linearGradient>
              </defs>
              <line x1="100" y1="80" x2="100" y2="320" :stroke="item.colors.leftColor" stroke-width="88" stroke-linecap="round" />
              <line x1="300" y1="80" x2="300" y2="320" :stroke="item.colors.rightColor" stroke-width="88" stroke-linecap="round" />
              <line x1="100" y1="80" x2="300" y2="320" :stroke="'url(#collGrad' + idx + ')'" stroke-width="88" stroke-linecap="round" opacity="0.85" />
            </svg>
          </div>
          <span class="collection-name">{{ item.name }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'

const crystals = ref(16000)
const gameState = ref('lobby') // lobby, animation, single-reveal, ten-reveal
const pity5StarCount = ref(0)
const pity4StarCount = ref(0)
const revealList = ref([])
const unlockedList = ref([])
const detailCard = ref(null)
const highestRarity = ref(3)
const isMuted = ref(false)

const copyBtnText = ref('复制 SVG 代码')
const copyBtnTextVector = ref('复制 Vector XML')

// audio helpers
let audioCtx = null

const initAudio = () => {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)()
  }
}

const playSound = (freq, duration, type = 'sine', gainVal = 0.15) => {
  if (isMuted.value) return
  initAudio()
  try {
    const osc = audioCtx.createOscillator()
    const gainNode = audioCtx.createGain()
    osc.type = type
    osc.frequency.setValueAtTime(freq, audioCtx.currentTime)
    gainNode.gain.setValueAtTime(gainVal, audioCtx.currentTime)
    gainNode.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + duration)
    osc.connect(gainNode)
    gainNode.connect(audioCtx.destination)
    osc.start()
    osc.stop(audioCtx.currentTime + duration)
  } catch (err) {
    console.warn('Audio play block:', err)
  }
}

const playWhoosh = () => {
  if (isMuted.value) return
  initAudio()
  try {
    const osc = audioCtx.createOscillator()
    const gainNode = audioCtx.createGain()
    osc.type = 'sawtooth'
    osc.frequency.setValueAtTime(100, audioCtx.currentTime)
    osc.frequency.exponentialRampToValueAtTime(800, audioCtx.currentTime + 1.2)
    gainNode.gain.setValueAtTime(0.01, audioCtx.currentTime)
    gainNode.gain.linearRampToValueAtTime(0.12, audioCtx.currentTime + 0.3)
    gainNode.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + 1.2)
    osc.connect(gainNode)
    gainNode.connect(audioCtx.destination)
    osc.start()
    osc.stop(audioCtx.currentTime + 1.2)
  } catch (err) {}
}

const playRevealSound = (rarity) => {
  if (isMuted.value) return
  if (rarity === 5) {
    // 5星宏大金光钟声
    playSound(261.63, 0.4, 'sine', 0.25) // C4
    setTimeout(() => playSound(329.63, 0.4, 'sine', 0.25), 150) // E4
    setTimeout(() => playSound(392.00, 0.4, 'sine', 0.25), 300) // G4
    setTimeout(() => playSound(523.25, 0.8, 'triangle', 0.35), 450) // C5
  } else if (rarity === 4) {
    // 4星风铃闪烁
    playSound(440, 0.3, 'sine', 0.2) // A4
    setTimeout(() => playSound(554.37, 0.3, 'sine', 0.2), 100) // C#5
    setTimeout(() => playSound(659.25, 0.5, 'sine', 0.25), 200) // E5
  } else {
    // 3星简单和弦
    playSound(329.63, 0.3, 'sine', 0.15) // E4
    setTimeout(() => playSound(392.00, 0.4, 'sine', 0.15), 100) // G4
  }
}

const toggleMute = () => {
  isMuted.value = !isMuted.value
  if (!isMuted.value) {
    initAudio()
    // 播放点击音
    playSound(523.25, 0.1)
  }
}

// 预设5星 & 4星卡牌池
const pool5Star = [
  {
    id: 'aurora',
    name: '极光幻夜',
    rarity: 5,
    desc: '模拟北极夜空的魔幻极光，青与紫的交织如梦如幻。',
    colors: {
      leftColor: '#80DEEA',
      rightColor: '#E1BEE7',
      gradStart: '#006064',
      gradStop2: '#00838F',
      gradStop3: '#8E24AA',
      gradEnd: '#4A148C'
    }
  },
  {
    id: 'inferno',
    name: '红莲劫火',
    rarity: 5,
    desc: '凝聚了火山深处最炽烈的火种，具有极致的侵略性与热情。',
    colors: {
      leftColor: '#FF8A80',
      rightColor: '#FF5252',
      gradStart: '#3700B3',
      gradStop2: '#D50000',
      gradStop3: '#FF1744',
      gradEnd: '#800808'
    }
  },
  {
    id: 'amber',
    name: '金枫圣芒',
    rarity: 5,
    desc: '融汇了秋日落叶与黄金余晖的圣神光芒，代表极致的高贵与防御。',
    colors: {
      leftColor: '#FFE082',
      rightColor: '#FFB74D',
      gradStart: '#FFF8E1',
      gradStop2: '#FFD54F',
      gradStop3: '#FFB300',
      gradEnd: '#FF8F00'
    }
  }
]

const pool4Star = [
  {
    id: 'lavender',
    name: '薰衣草幻境',
    rarity: 4,
    desc: '迷雾中若隐若现的薰衣草田，带来静谧、幽雅与舒适的视觉享受。',
    colors: {
      leftColor: '#D0BCFF',
      rightColor: '#EFB8C8',
      gradStart: '#4F378B',
      gradStop2: '#6750A4',
      gradStop3: '#9A82DB',
      gradEnd: '#381E72'
    }
  },
  {
    id: 'mint',
    name: '夏日清荷',
    rarity: 4,
    desc: '清凉薄荷色系交织，仿佛夏日池塘中盛开的青绿荷叶与微风。',
    colors: {
      leftColor: '#A7F3D0',
      rightColor: '#FDE047',
      gradStart: '#064E3B',
      gradStop2: '#059669',
      gradStop3: '#34D399',
      gradEnd: '#022C22'
    }
  },
  {
    id: 'watcher',
    name: '深渊之眼',
    rarity: 4,
    desc: '蔚蓝深邃的海洋与星辰之光的呼应，科技感十足。',
    colors: {
      leftColor: '#93C5FD',
      rightColor: '#C084FC',
      gradStart: '#1E3A8A',
      gradStop2: '#2563EB',
      gradStop3: '#60A5FA',
      gradEnd: '#172554'
    }
  },
  {
    id: 'sakura',
    name: '绯樱落羽',
    rarity: 4,
    desc: '漫天飞舞的樱花花瓣，如同初春的恋爱般细腻温暖。',
    colors: {
      leftColor: '#FBCFE8',
      rightColor: '#FCA5A5',
      gradStart: '#881337',
      gradStop2: '#DB2777',
      gradStop3: '#F472B6',
      gradEnd: '#4C0519'
    }
  }
]

// 颜色模型算法 (用于随机生成 3 星色彩)
function hexToHsl(hex) {
  hex = hex.replace(/^#/, '')
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
  return { h: Math.round(h * 360), s: Math.round(s * 100), l: Math.round(l * 100) }
}

function hslToHex(h, s, l) {
  h /= 360; s /= 100; l /= 100
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

// 随机生成 3 星色彩
const generateRandom3Star = () => {
  const suffixes = ['幽绿', '赤红', '晶蓝', '松石', '冷灰', '金砂', '暮紫', '幻青']
  const suf = suffixes[Math.floor(Math.random() * suffixes.length)]
  const randHue = Math.floor(Math.random() * 360)
  
  // 生成 Monet 调色板
  const leftColor = hslToHex((randHue - 32 + 360) % 360, 75, 62)
  const rightColor = hslToHex((randHue + 38) % 360, 70, 70)
  const gradStart = hslToHex(randHue, 80, 42)
  const gradStop2 = hslToHex((randHue + 8) % 360, 75, 55)
  const gradStop3 = hslToHex((randHue + 24) % 360, 65, 68)
  const gradEnd = hslToHex((randHue - 15 + 360) % 360, 80, 30)

  return {
    id: 'star3_' + Math.random().toString(36).substr(2, 9),
    name: '量子' + suf,
    rarity: 3,
    desc: '通过量子引擎生成的普通等级常驻莫奈配色。',
    colors: { leftColor, rightColor, gradStart, gradStop2, gradStop3, gradEnd }
  }
}

// 抽卡核心逻辑
const rollOne = () => {
  pity5StarCount.value++
  pity4StarCount.value++
  
  // 5星判定 (保底 80 抽)
  if (pity5StarCount.value >= 80) {
    pity5StarCount.value = 0
    pity4StarCount.value = 0 // 5星也会消耗4星保底
    return { ...pool5Star[Math.floor(Math.random() * pool5Star.length)] }
  }

  // 4星判定 (保底 10 抽)
  if (pity4StarCount.value >= 10) {
    pity4StarCount.value = 0
    return { ...pool4Star[Math.floor(Math.random() * pool4Star.length)] }
  }

  // 正常概率检查
  const rand = Math.random() * 100
  if (rand < 1.6) { // 1.6% 5星
    pity5StarCount.value = 0
    pity4StarCount.value = 0
    return { ...pool5Star[Math.floor(Math.random() * pool5Star.length)] }
  } else if (rand < 1.6 + 8.4) { // 8.4% 4星
    pity4StarCount.value = 0
    return { ...pool4Star[Math.floor(Math.random() * pool4Star.length)] }
  } else {
    return generateRandom3Star()
  }
}

const performWish = (count) => {
  const cost = count === 10 ? 1600 : 160
  if (crystals.value < cost) {
    // 自动补充原石以便用户无限测试！
    crystals.value += 16000
    playSound(587.33, 0.15)
  }
  crystals.value -= cost

  // 播放点击 & 祈愿起飞声
  playSound(523.25, 0.1)
  setTimeout(() => playWhoosh(), 100)

  // 抽卡
  const results = []
  for (let i = 0; i < count; i++) {
    results.push(rollOne())
  }
  revealList.value = results

  // 找出最高稀有度
  highestRarity.value = Math.max(...results.map(x => x.rarity))

  // 进入流星动画
  gameState.value = 'animation'

  // 自动过渡：2.2 秒后自动跳过流星划过动画进入展示界面
  setTimeout(() => {
    if (gameState.value === 'animation') {
      skipAnimation()
    }
  }, 2200)
}

const highestRarityClass = computed(() => {
  if (highestRarity.value === 5) return 'gold-meteor'
  if (highestRarity.value === 4) return 'purple-meteor'
  return 'blue-meteor'
})

const getRarityClass = (rarity) => {
  if (rarity === 5) return 'rarity-5'
  if (rarity === 4) return 'rarity-4'
  return 'rarity-3'
}

const skipAnimation = () => {
  playRevealSound(highestRarity.value)
  if (revealList.value.length === 1) {
    gameState.value = 'single-reveal'
  } else {
    gameState.value = 'ten-reveal'
  }
}

const closeReveal = () => {
  // 记录到已解锁图鉴
  revealList.value.forEach(item => {
    if (!unlockedList.value.some(x => x.name === item.name)) {
      unlockedList.value.push(item)
    }
  })
  gameState.value = 'lobby'
  detailCard.value = null
  revealList.value = []
}

const selectDetailCard = (item) => {
  detailCard.value = item
  playSound(659.25, 0.1)
}

// 复制代码功能
const copyRevealCode = async (item, format) => {
  initAudio()
  let code = ''
  if (format === 'svg') {
    code = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" width="100%" height="100%">
  <defs>
    <linearGradient id="diagGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${item.colors.gradStart}" />
      <stop offset="35%" stop-color="${item.colors.gradStop2}" />
      <stop offset="65%" stop-color="${item.colors.gradStop3}" />
      <stop offset="100%" stop-color="${item.colors.gradEnd}" />
    </linearGradient>
  </defs>
  <line x1="100" y1="80" x2="100" y2="320" stroke="${item.colors.leftColor}" stroke-width="88" stroke-linecap="round" />
  <line x1="300" y1="80" x2="300" y2="320" stroke="${item.colors.rightColor}" stroke-width="88" stroke-linecap="round" />
  <line x1="100" y1="80" x2="300" y2="320" stroke="url(#diagGrad)" stroke-width="88" stroke-linecap="round" opacity="0.85" />
</svg>`
  } else {
    code = `<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="400dp"
    android:height="400dp"
    android:viewportWidth="400"
    android:viewportHeight="400">
    <path
        android:pathData="M 100,80 L 100,320"
        android:strokeColor="${item.colors.leftColor}"
        android:strokeWidth="88"
        android:strokeLineCap="round" />
    <path
        android:pathData="M 300,80 L 300,320"
        android:strokeColor="${item.colors.rightColor}"
        android:strokeWidth="88"
        android:strokeLineCap="round" />
    <path
        android:pathData="M 100,80 L 300,320"
        android:strokeWidth="88"
        android:strokeLineCap="round"
        android:strokeAlpha="0.85">
        <aapt:attr name="android:strokeColor">
            <gradient
                android:startX="100"
                android:startY="80"
                android:endX="300"
                android:endY="320"
                android:type="linear">
                <item android:offset="0.0" android:color="${item.colors.gradStart}" />
                <item android:offset="0.35" android:color="${item.colors.gradStop2}" />
                <item android:offset="0.65" android:color="${item.colors.gradStop3}" />
                <item android:offset="1.0" android:color="${item.colors.gradEnd}" />
            </gradient>
        </aapt:attr>
    </path>
</vector>`
  }

  try {
    await navigator.clipboard.writeText(code)
    if (format === 'svg') {
      copyBtnText.value = '已复制 SVG！'
      playSound(880, 0.15)
      setTimeout(() => copyBtnText.value = '复制 SVG 代码', 2000)
    } else {
      copyBtnTextVector.value = '已复制 XML！'
      playSound(880, 0.15)
      setTimeout(() => copyBtnTextVector.value = '复制 Vector XML', 2000)
    }
  } catch (err) {
    if (format === 'svg') copyBtnText.value = '复制失败'
    else copyBtnTextVector.value = '复制失败'
  }
}
</script>

<style scoped>
/* 祈愿模拟器独立样式 */
.gacha-game-container {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  margin-top: 1.5rem;
  font-family: var(--vp-font-family-base);
  color: #fff;
  background-color: #0b0b12;
  padding: 1.5rem;
  border-radius: 18px;
  border: 1px solid #1a1a2e;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
  position: relative;
  overflow: hidden;
}

.gacha-game-container::before {
  content: '';
  position: absolute;
  top: -50%;
  left: -50%;
  width: 200%;
  height: 200%;
  background: radial-gradient(circle, rgba(29,78,216,0.08) 0%, transparent 60%);
  pointer-events: none;
}

/* 头部显示 */
.game-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  z-index: 5;
}

.crystal-display {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  background-color: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.12);
  padding: 0.4rem 1rem;
  border-radius: 20px;
  font-weight: 700;
  font-size: 1.05rem;
}

.sound-toggle {
  font-size: 1.25rem;
  background: none;
  border: none;
  cursor: pointer;
  opacity: 0.7;
  transition: opacity 0.2s;
}

.sound-toggle:hover {
  opacity: 1;
}

/* 祈愿大厅 */
.banner-lobby {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  align-items: center;
  z-index: 5;
}

.banner-card {
  width: 100%;
  background: linear-gradient(135deg, #111122 0%, #1c1c38 100%);
  border: 1px solid #2d2d5a;
  border-radius: 16px;
  padding: 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  box-shadow: inset 0 0 20px rgba(0,0,0,0.5);
}

@media (min-width: 768px) {
  .banner-card {
    flex-direction: row;
    justify-content: space-between;
    align-items: center;
  }
}

.banner-title-area {
  flex-grow: 1;
}

.banner-tag {
  background-color: #ff9f0a;
  color: #000;
  font-size: 0.75rem;
  font-weight: 800;
  padding: 0.2rem 0.5rem;
  border-radius: 4px;
  text-transform: uppercase;
}

.banner-title {
  margin: 0.5rem 0 0.3rem 0 !important;
  font-size: 1.6rem;
  font-weight: 800;
  color: #fff;
  border-bottom: none !important;
  padding: 0 !important;
}

.banner-desc {
  margin: 0 !important;
  font-size: 0.85rem;
  color: #a0a0c0;
}

.featured-items {
  display: flex;
  gap: 1rem;
}

.featured-card {
  background-color: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 12px;
  padding: 0.6rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.3rem;
  transition: transform 0.2s;
}

.featured-card:hover {
  transform: translateY(-4px);
}

.aurora-mini {
  border-color: rgba(142, 36, 170, 0.4);
  box-shadow: 0 4px 12px rgba(142, 36, 170, 0.15);
}

.inferno-mini {
  border-color: rgba(255, 23, 68, 0.4);
  box-shadow: 0 4px 12px rgba(255, 23, 68, 0.15);
}

.feat-name {
  font-size: 0.8rem;
  font-weight: 700;
}

.feat-stars {
  font-size: 0.65rem;
}

/* 祈愿按钮 */
.gacha-actions {
  display: flex;
  gap: 1.2rem;
  width: 100%;
  max-width: 500px;
}

.gacha-btn {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.15rem;
  padding: 0.8rem 1rem;
  border-radius: 30px;
  border: none;
  font-weight: 700;
  cursor: pointer;
  transition: all 0.2s;
}

.single-pull {
  background-color: #3b82f6;
  color: #fff;
  box-shadow: 0 4px 15px rgba(59, 130, 246, 0.4);
}

.single-pull:hover {
  background-color: #2563eb;
  transform: scale(1.03);
}

.ten-pull {
  background: linear-gradient(90deg, #d97706, #ff9f0a);
  color: #000;
  box-shadow: 0 4px 15px rgba(217, 119, 6, 0.4);
}

.ten-pull:hover {
  background: linear-gradient(90deg, #b45309, #d97706);
  transform: scale(1.03);
  color: #fff;
}

.btn-text {
  font-size: 1rem;
}

.btn-cost {
  font-size: 0.75rem;
  opacity: 0.9;
}

.pity-counter {
  font-size: 0.8rem;
  color: #707090;
}

/* 祈愿大屏图层 */
.gacha-wish-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background-color: #020208;
  z-index: 1000;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  overflow-y: auto;
  padding: 2rem;
  box-sizing: border-box;
}

.animation-stage-inner {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  z-index: 2;
}

.skip-tip {
  position: absolute;
  top: 1.5rem;
  right: 1.5rem;
  background-color: rgba(255, 255, 255, 0.1);
  padding: 0.4rem 1rem;
  border-radius: 20px;
  font-size: 0.8rem;
  color: rgba(255, 255, 255, 0.6);
  z-index: 10;
}

/* 流星轨迹核心动画 */
.meteor-trail {
  position: absolute;
  width: 4px;
  height: 150px;
  transform: rotate(-45deg);
  top: -200px;
  left: 120%;
  animation: shoot 1.8s cubic-bezier(0.25, 1, 0.5, 1) forwards;
  z-index: 3;
}

@keyframes shoot {
  0% {
    top: -200px;
    left: 120%;
    opacity: 1;
  }
  100% {
    top: 120%;
    left: -20%;
    opacity: 0;
  }
}

.blue-meteor {
  background: linear-gradient(to top, rgba(59, 130, 246, 1), transparent);
  box-shadow: 0 0 20px rgba(59, 130, 246, 0.8);
}

.purple-meteor {
  background: linear-gradient(to top, rgba(168, 85, 247, 1), transparent);
  box-shadow: 0 0 30px rgba(168, 85, 247, 0.9);
}

.gold-meteor {
  background: linear-gradient(to top, rgba(234, 179, 8, 1), transparent);
  box-shadow: 0 0 45px rgba(234, 179, 8, 1), 0 0 10px rgba(255, 255, 255, 1);
  width: 6px;
}

/* 星空粒子背景 */
.stars-particle-bg {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-image: 
    radial-gradient(1px 1px at 20px 30px, #eee, transparent),
    radial-gradient(1px 1px at 40px 70px, #fff, transparent),
    radial-gradient(2px 2px at 90px 110px, rgba(255,255,255,0.5), transparent),
    radial-gradient(1px 1px at 150px 200px, #ddd, transparent);
  background-size: 200px 200px;
  opacity: 0.4;
  pointer-events: none;
  z-index: 1;
}

.nebula-glow {
  position: absolute;
  top: 50%;
  left: 50%;
  width: 500px;
  height: 500px;
  transform: translate(-50%, -50%);
  background: radial-gradient(circle, rgba(142,36,170,0.18) 0%, rgba(29,78,216,0.12) 40%, transparent 70%);
  filter: blur(60px);
  pointer-events: none;
  animation: pulseNebula 12s ease-in-out infinite alternate;
  z-index: 1;
}

@keyframes pulseNebula {
  0% { transform: translate(-50%, -50%) scale(1) rotate(0deg); opacity: 0.5; }
  100% { transform: translate(-50%, -50%) scale(1.3) rotate(360deg); opacity: 0.9; }
}

/* 卡牌展示 */
.reveal-stage {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1.5rem;
  width: 100%;
  z-index: 5;
  padding: 1rem 0;
}

.card-display-container {
  perspective: 1000px;
}

.card-frame {
  width: 280px;
  height: 420px;
  border-radius: 20px;
  padding: 3px;
  position: relative;
  overflow: hidden;
  box-shadow: 0 15px 35px rgba(0, 0, 0, 0.6);
  animation: cardFlipIn 0.8s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards;
  transform-style: preserve-3d;
}

@keyframes cardFlipIn {
  from {
    transform: rotateY(90deg) scale(0.7);
    opacity: 0;
  }
  to {
    transform: rotateY(0deg) scale(1);
    opacity: 1;
  }
}

.card-frame::before {
  content: '';
  position: absolute;
  top: -50%;
  left: -50%;
  width: 200%;
  height: 200%;
  background: conic-gradient(transparent, var(--rarity-glow-color), transparent 30%);
  animation: rotateGlow 4s linear infinite;
}

@keyframes rotateGlow {
  100% { transform: rotate(360deg); }
}

.rarity-5 {
  --rarity-glow-color: #eab308;
  background: linear-gradient(135deg, #eab308 0%, #ca8a04 100%);
  box-shadow: 0 0 25px rgba(234, 179, 8, 0.4);
}

.rarity-4 {
  --rarity-glow-color: #a855f7;
  background: linear-gradient(135deg, #a855f7 0%, #7e22ce 100%);
  box-shadow: 0 0 20px rgba(168, 85, 247, 0.3);
}

.rarity-3 {
  --rarity-glow-color: #3b82f6;
  background: linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%);
}

.card-glow {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: linear-gradient(135deg, rgba(255,255,255,0.2) 0%, transparent 50%, rgba(0,0,0,0.4) 100%);
  pointer-events: none;
  z-index: 3;
}

.card-inner {
  background-color: #12121e;
  border-radius: 17px;
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  padding: 1.25rem;
  position: relative;
  z-index: 2;
}

.card-header-info {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.card-stars {
  font-size: 0.95rem;
}

.card-rarity-text {
  font-size: 0.75rem;
  color: #707090;
  text-transform: uppercase;
}

.card-svg-view {
  flex-grow: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  max-height: 220px;
  padding: 1.5rem;
  filter: drop-shadow(0 8px 16px rgba(0,0,0,0.5));
}

.card-footer-info {
  text-align: center;
}

.card-title {
  margin: 0 0 0.4rem 0 !important;
  font-size: 1.3rem;
  font-weight: 800;
  color: #fff;
  border-bottom: none !important;
  padding: 0 !important;
}

.card-desc {
  margin: 0 !important;
  font-size: 0.75rem;
  color: #8c8ca8;
  line-height: 1.3;
}

/* 按钮组 */
.reveal-actions {
  display: flex;
  gap: 0.8rem;
  width: 100%;
  max-width: 480px;
  margin-top: 1rem;
}

.action-btn {
  flex: 1;
  padding: 0.6rem 1rem;
  border-radius: 8px;
  border: 1px solid var(--vp-c-brand);
  background-color: var(--vp-c-brand);
  color: var(--vp-c-bg);
  font-weight: 600;
  cursor: pointer;
  font-size: 0.85rem;
  transition: all 0.2s;
  text-align: center;
}

.action-btn:hover {
  background-color: var(--vp-c-brand-dark);
  border-color: var(--vp-c-brand-dark);
}

.btn-secondary {
  background-color: transparent;
  color: var(--vp-c-brand);
  border-color: var(--vp-c-brand);
}

.btn-secondary:hover {
  background-color: var(--vp-c-brand-soft);
}

.btn-confirm {
  background-color: #10b981;
  border-color: #10b981;
  color: #000;
}

.btn-confirm:hover {
  background-color: #059669;
  border-color: #059669;
  color: #fff;
}

/* 十连展示网格 */
.ten-reveal-title {
  margin-top: 0 !important;
  font-size: 1.3rem;
  font-weight: 800;
  color: #fff;
}

.ten-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 0.75rem;
  width: 100%;
}

@media (min-width: 768px) {
  .ten-grid {
    grid-template-columns: repeat(5, 1fr);
  }
}

.grid-card {
  background-color: #12121e;
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 12px;
  padding: 0.8rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  cursor: pointer;
  transition: all 0.2s;
  opacity: 0;
  transform: translateY(30px);
  animation: cardSlideIn 0.5s cubic-bezier(0.25, 1, 0.5, 1) forwards;
}

/* Stagger delays for ten pull items */
.grid-card:nth-child(1) { animation-delay: 0.05s; }
.grid-card:nth-child(2) { animation-delay: 0.10s; }
.grid-card:nth-child(3) { animation-delay: 0.15s; }
.grid-card:nth-child(4) { animation-delay: 0.20s; }
.grid-card:nth-child(5) { animation-delay: 0.25s; }
.grid-card:nth-child(6) { animation-delay: 0.30s; }
.grid-card:nth-child(7) { animation-delay: 0.35s; }
.grid-card:nth-child(8) { animation-delay: 0.40s; }
.grid-card:nth-child(9) { animation-delay: 0.45s; }
.grid-card:nth-child(10) { animation-delay: 0.50s; }

@keyframes cardSlideIn {
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.grid-card:hover {
  transform: translateY(-4px) scale(1.02);
}

.grid-card.rarity-5 {
  border-color: #ca8a04;
  box-shadow: 0 4px 12px rgba(234, 179, 8, 0.15);
}

.grid-card.rarity-4 {
  border-color: #7e22ce;
  box-shadow: 0 4px 12px rgba(168, 85, 247, 0.12);
}

.grid-card-svg {
  filter: drop-shadow(0 4px 8px rgba(0,0,0,0.4));
}

.grid-card-info {
  display: flex;
  flex-direction: column;
  align-items: center;
}

.grid-card-name {
  font-size: 0.75rem;
  font-weight: 700;
  text-align: center;
}

.grid-card-stars {
  font-size: 0.6rem;
  color: #ff9f0a;
}

/* 模态弹窗 */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background-color: rgba(0,0,0,0.85);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1010;
  padding: 1.5rem;
}

.modal-content {
  background-color: #0f0f18;
  border: 1px solid #1a1a2e;
  border-radius: 20px;
  padding: 1.5rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1.2rem;
  width: 100%;
  max-width: 380px;
}

.card-frame.compact {
  height: 330px;
  width: 220px;
}

.card-frame.compact .card-desc {
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.card-frame.compact .card-svg-view {
  max-height: 140px;
  padding: 0.5rem;
}

.modal-actions {
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
  width: 100%;
}

/* 图鉴面板 */
.collection-section {
  background-color: rgba(255, 255, 255, 0.02);
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 16px;
  padding: 1.5rem;
  margin-top: 1.5rem;
}

.empty-collection {
  text-align: center;
  color: #505070;
  font-size: 0.85rem;
  padding: 2rem 0;
}

.collection-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.8rem;
}

@media (min-width: 768px) {
  .collection-grid {
    grid-template-columns: repeat(6, 1fr);
  }
}

.collection-item {
  background-color: rgba(0, 0, 0, 0.2);
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 12px;
  padding: 0.6rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.4rem;
  cursor: pointer;
  transition: all 0.2s;
}

.collection-item:hover {
  transform: translateY(-2px);
  background-color: rgba(255, 255, 255, 0.04);
}

.collection-item.rarity-5 {
  border-color: rgba(234, 179, 8, 0.3);
}

.collection-item.rarity-4 {
  border-color: rgba(168, 85, 247, 0.3);
}

.collection-item.rarity-3 {
  border-color: rgba(59, 130, 246, 0.2);
}

.collection-name {
  font-size: 0.7rem;
  text-align: center;
  color: #ccc;
}
</style>
