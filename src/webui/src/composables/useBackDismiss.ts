/**
 * @file useBackDismiss.ts
 * @description 让弹窗/菜单接入返回手势：手机手势返回（或浏览器后退）时优先关闭弹窗、
 *   页面不切。实现走 vue-router 的 query 标记（单一历史源，不直接操作 history，
 *   避免与 vue-router 的 popstate/position 计数冲突）：
 *     - 弹窗打开 → router.push 在当前路径上追加 query 标记（新增一个历史条目）；
 *     - 用户返回 → vue-router 弹掉该 query → 监听到标记消失即关闭弹窗，路径不变；
 *     - UI 主动关闭 → router.back() 弹掉标记，保持历史平衡。
 */
import { watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

let markerSeq = 0;

/**
 * 注册弹窗返回拦截。
 * @param isOpen   聚合 getter：该组件是否有任意弹窗/菜单打开
 * @param closeAll 关闭该组件全部弹窗/菜单
 */
export function useBackDismiss(isOpen: () => boolean, closeAll: () => void): void {
  const route = useRoute();
  const router = useRouter();
  const markerId = `d${++markerSeq}`;
  let suppress = false; // UI 主动关闭触发的 back，避免重复关闭

  // 弹窗开关 → 维护 query 标记（历史条目）
  watch(isOpen, (open, prev) => {
    if (open && !prev) {
      // 打开：追加 query 标记，新增一个可被返回消费的历史条目
      router.push({ path: route.path, query: { ...route.query, dlg: markerId } });
    } else if (!open && prev) {
      // UI 主动关闭：若标记仍在则弹掉，保持历史平衡
      if (route.query.dlg === markerId) {
        suppress = true;
        router.back();
      }
    }
  });

  // 标记从路由消失（用户返回）→ 若弹窗仍开则关闭
  watch(
    () => route.query.dlg,
    (val, old) => {
      if (suppress) {
        suppress = false;
        return;
      }
      if (old === markerId && val !== markerId && isOpen()) {
        closeAll();
      }
    }
  );
}
