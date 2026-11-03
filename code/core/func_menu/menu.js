/* PopoHere · 菜单桥
 *
 * 职责
 *   菜单界面由独立的面板窗口承载（同目录 panel.html，由外壳创建）。
 *   本模块只做两件事：
 *     1. 右键桌宠时把光标的屏幕坐标交给外壳，由外壳决定打开或收起面板；
 *     2. 面板真正收起时，把状态机从 menu 状态带回静息。
 *
 * 采用独立窗口的原因
 *   桌宠窗口的尺寸只等于贴图大小，菜单需要能展开到该范围之外；
 *   同时面板需要自己的圆角、投影与失焦收起行为，与桌宠窗口互不干扰。
 *
 * 状态归属
 *   menu 状态由「面板是否真的显示」单向驱动，本模块不自行切换状态。
 *
 * 对外暴露：Popo.createMenu({ el, machine, post, native, log })
 */
(function (root) {
  root.Popo = root.Popo || {};

  function createMenu(opts) {
    const el = opts.el;
    const machine = opts.machine;
    const post = opts.post || function () {};
    const native = !!opts.native;
    const log = opts.log || function () {};

    /* 由外壳在面板确实收起时回调，是离开 menu 状态的唯一入口 */
    function notifyClosed() {
      machine.closeMenu();
    }

    if (el.desktop) {
      el.desktop.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        if (!native) {
          log('右键菜单在正式版（.app）里可用');
          return;
        }
        // 仅请求外壳处理面板的开合（已显示则收起，由外壳判断）。
        // menu 状态由外壳在面板显示后回调 menuOpened() 设置，
        // 避免页面与外壳各自维护状态导致不一致。
        post({ type: 'openMenu', x: e.screenX, y: e.screenY });
      });
    }

    return { notifyClosed: notifyClosed };
  }

  root.Popo.createMenu = createMenu;
})(typeof globalThis !== 'undefined' ? globalThis : this);
