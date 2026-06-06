import DefaultTheme from 'vitepress/theme'
import MonetEditor from './components/MonetEditor.vue'
import GachaSimulator from './components/GachaSimulator.vue'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('MonetEditor', MonetEditor)
    app.component('GachaSimulator', GachaSimulator)
  }
}
