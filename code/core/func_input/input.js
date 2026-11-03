/* PopoHere · 鼠标输入
 *
 * 职责
 *   1. 命中判定：换算主题里的相对坐标，决定点击落在哪个区域；
 *   2. 区分单击与拖拽：位移与时长同时满足阈值才计为单击；
 *   3. 抱起时的位移：网页预览模式直接移动 DOM，原生模式交由外壳处理。
 *
 * 坐标约定（与 doc/UserGuide.md「拖拽」一节对应）
 *   位移一律使用屏幕坐标 screenX / screenY 计算。原因是原生模式下移动的是
 *   「承载页面的窗口」本身，视口会随窗口一起位移，clientX 因此无法反映真实位移。
 *   原生模式下本模块只上报 press / release 两个事件，窗口位移由外壳用
 *   NSEvent 的屏幕坐标同步完成。
 *
 * 对外暴露：Popo.createInput({ el, theme, machine, native, post, ... })
 */
(function (root) {
  root.Popo = root.Popo || {};

  function createInput(opts) {
    const el = opts.el;
    const theme = opts.theme;
    const machine = opts.machine;
    const native = !!opts.native;
    const post = opts.post || function () {};
    const getSize = opts.getSize;
    const getDefaultPos = opts.getDefaultPos;

    const drag = {
      active: false, startX: 0, startY: 0, dist: 0, t0: 0,
      baseLeft: 0, baseTop: 0,
    };

    // 单一命中区：整只桌宠都是可点击区域，不区分部位
    function layoutHitboxes() {
      const r = theme.hitBoxes.body;
      const size = getSize();
      const node = el.hbBody;
      if (!r || !node) return;
      node.style.left = r.x * size + 'px';
      node.style.top = r.y * size + 'px';
      node.style.width = r.w * size + 'px';
      node.style.height = r.h * size + 'px';
    }

    el.pet.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      drag.active = true;
      drag.dist = 0;
      drag.t0 = performance.now();
      drag.startX = e.screenX;
      drag.startY = e.screenY;

      machine.pressStart('body');

      // 起始位置仅在网页预览模式下使用；原生模式的位移由外壳接管
      if (!native) {
        const dp = getDefaultPos();
        drag.baseLeft = parseFloat(el.pet.style.left) || dp.left;
        drag.baseTop = parseFloat(el.pet.style.top) || dp.top;
      }

      // 原生模式仅上报按下事件，后续位移由外壳跟踪
      if (native) post({ type: 'press' });
    });

    window.addEventListener('mousemove', (e) => {
      if (!drag.active) return;
      const dx = e.screenX - drag.startX;
      const dy = e.screenY - drag.startY;
      drag.dist = Math.hypot(dx, dy);
      const carrying = machine.pressMove(drag.dist);   // 只推进状态机，不负责移动

      if (carrying && !native) {
        // 网页预览模式：直接移动 DOM
        const size = getSize();
        const maxL = el.stage.clientWidth - size;
        const maxT = el.stage.clientHeight - size;
        el.pet.style.left = Math.max(0, Math.min(maxL, drag.baseLeft + dx)) + 'px';
        el.pet.style.top = Math.max(28, Math.min(maxT, drag.baseTop + dy)) + 'px';
      }
    });

    function finishPress() {
      if (!drag.active) return;
      drag.active = false;
      const wasCarrying = machine._carrying;
      machine.pressEnd(performance.now() - drag.t0);
      if (native) post({ type: 'release', carried: wasCarrying });
      el.pet.classList.toggle('carrying', machine._carrying);
    }

    window.addEventListener('mouseup', finishPress);

    // 兜底：网页失去焦点时收不到 mouseup，若不处理会导致按压状态卡死，后续点击全部失效
    window.addEventListener('blur', finishPress);

    return { layoutHitboxes: layoutHitboxes };
  }

  root.Popo.createInput = createInput;
})(typeof globalThis !== 'undefined' ? globalThis : this);
