/**
 * @file i18n/index.ts
 * @description vue-i18n（Composition 模式）初始化与语言管理。
 *   支持 zh-CN / en-US / ru-RU 三种语言：首次按系统语言决定，
 *   用户在设置页切换后以 localStorage 保存值为准。
 */
import { createI18n } from 'vue-i18n';
import zhCN from './locales/zh-CN.json';
import enUS from './locales/en-US.json';
import ruRU from './locales/ru-RU.json';

/** 支持的语言标识。 */
export type LocaleCode = 'zh-CN' | 'en-US' | 'ru-RU';

/** 语言选项（用于设置页下拉，display 取自各 locale 的 lang.display）。 */
export const SUPPORTED_LOCALES: LocaleCode[] = ['zh-CN', 'en-US', 'ru-RU'];

const STORAGE_KEY = 'np_locale';
const FALLBACK: LocaleCode = 'zh-CN';

/**
 * 决定初始语言：优先 localStorage 保存值；否则按 navigator.language
 * 匹配（ru*→俄、en*→英、其余→中）。
 */
export const detectInitialLocale = (): LocaleCode => {
  const saved = localStorage.getItem(STORAGE_KEY) as LocaleCode | null;
  if (saved && SUPPORTED_LOCALES.includes(saved)) return saved;

  const sys = (navigator.language || '').toLowerCase();
  if (sys.startsWith('ru')) return 'ru-RU';
  if (sys.startsWith('en')) return 'en-US';
  return FALLBACK;
};

export const i18n = createI18n({
  legacy: false,                 // Composition API 模式：组件内用 useI18n()
  locale: detectInitialLocale(),
  fallbackLocale: FALLBACK,
  messages: {
    'zh-CN': zhCN,
    'en-US': enUS,
    'ru-RU': ruRU
  }
});

/**
 * 切换语言：更新 i18n、持久化、并同步 <html lang>。
 * vue-i18n 响应式，调用后全界面立即更新，无需刷新。
 * @param locale  目标语言
 */
export const setLocale = (locale: LocaleCode): void => {
  i18n.global.locale.value = locale;
  localStorage.setItem(STORAGE_KEY, locale);
  document.documentElement.lang = locale;
};

// 启动时同步一次 <html lang>
document.documentElement.lang = i18n.global.locale.value;
