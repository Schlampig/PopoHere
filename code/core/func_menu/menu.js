/* PopoHere · 菜单桥
 *
 * v2.0 起菜单不再画在宠物页面里，而是一个独立的透明玻璃面板窗口
 * （见同一目录下的 panel.html）。这里只负责：
 *   - 右键时告诉外壳"在光标处开菜单"
 *   - 菜单打开/关闭时，让状态机进入/离开 menu 状态
 *
 * 为什么要单独一个窗口：宠物窗口只有猫那么大，菜单要能展开到窗口之外；
 * 而且菜单需要自己的圆角/投影/失焦收起行为。
 *
 * 对外暴露：Popo.createMenu({ ... })
 */
(function (root) {
  root.Popo = root.Popo || {};

  function createMenu(opts) {
    const el = opts.el;
    const machine = opts.machine;
    const post = opts.post || function () {};
    const native = !!opts.native;
    const log = opts.log || function () {};

    let open = false;

    function close() {
      if (!open) return;
      open = false;
      machine.closeMenu();
    }

    /** 由外壳在面板真正收起时回调 */
    function notifyClosed() {
      open = false;
      machine.closeMenu();
    }

    if (el.desktop) {
      el.desktop.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        if (open) { close(); return; }
        if (!native) {
          log('右键菜单在正式版（.app）里可用');
          return;
        }
        // 屏幕上光标的绝对位置：面板窗口要贴着它弹出来
        open = true;
        machine.openMenu();
        post({ type: 'openMenu', x: e.screenX, y: e.screenY });
      });
    }

    return {
      close: close,
      notifyClosed: notifyClosed,
      isOpen: () => open,
    };
  }

  root.Popo.createMenu = createMenu;
})(typeof globalThis !== 'undefined' ? globalThis : this);
