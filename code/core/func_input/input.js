/* PopoHere · 鼠标输入
 *
 * 负责：命中判定（头/脚/空白）、单击 vs 拖拽的区分、抱起时的位移。
 * 不负责：状态怎么流转（交给状态机）、画面怎么画（交给渲染器）。
 *
 * 一条重要约定（详见 AGENTS.md「拖拽为什么会抖」）：
 *   - 位移一律用**屏幕坐标** e.screenX / e.screenY 计算。
 *   - 原生模式下这里不移动任何东西，只把"按下/松开"两个事件告诉外壳，
 *     真正的窗口移动由 Objective-C 侧用 NSEvent 屏幕坐标同步完成。
 *     曾经用 clientX 逐帧发包，会因视口随窗口移动形成反馈环 → 抖动。
 *
 * 对外暴露：Popo.createInput({ ... })
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
    const setPos = opts.setPos;

    const drag = {
      active: false, startX: 0, startY: 0, dist: 0, t0: 0, region: 'blank',
      baseLeft: 0, baseTop: 0,
    };

    function layoutHitboxes() {
      const bx = theme.hitBoxes;
      const size = getSize();
      for (const [name, node] of [['head', el.hbHead], ['paw', el.hbPaw]]) {
        const r = bx[name];
        if (!r || !node) continue;
        node.style.left = r.x * size + 'px';
        node.style.top = r.y * size + 'px';
        node.style.width = r.w * size + 'px';
        node.style.height = r.h * size + 'px';
      }
    }

    // offset 用相对宠物左上角的像素，换算成比例再查区域
    function regionAt(offsetX, offsetY) {
      const bx = theme.hitBoxes;
      const size = getSize();
      const fx = offsetX / size;
      const fy = offsetY / size;
      for (const name of ['head', 'paw']) {
        const r = bx[name];
        if (!r) continue;
        if (fx >= r.x && fx <= r.x + r.w && fy >= r.y && fy <= r.y + r.h) return name;
      }
      return 'blank';
    }

    el.pet.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      drag.active = true;
      drag.dist = 0;
      drag.t0 = performance.now();
      drag.startX = e.screenX;
      drag.startY = e.screenY;

      const rect = el.pet.getBoundingClientRect();
      drag.region = regionAt(e.clientX - rect.left, e.clientY - rect.top);
      machine.pressStart(drag.region);

      // 记录起始位置：仅网页预览模式用得到（原生模式由外壳用屏幕坐标接管）
      if (!native) {
        const dp = getDefaultPos();
        drag.baseLeft = parseFloat(el.pet.style.left) || dp.left;
        drag.baseTop = parseFloat(el.pet.style.top) || dp.top;
      }

      // 原生模式只通知"按下开始"，之后的位移由外壳跟踪
      if (native) post({ type: 'press' });
    });

    window.addEventListener('mousemove', (e) => {
      if (!drag.active) return;
      const dx = e.screenX - drag.startX;
      const dy = e.screenY - drag.startY;
      drag.dist = Math.hypot(dx, dy);
      const carrying = machine.pressMove(drag.dist);   // 只推进状态机，不负责移动

      if (carrying && !native) {
        // 网页预览模式：自己挪 DOM
        const size = getSize();
        const maxL = el.stage.clientWidth - size;
        const maxT = el.stage.clientHeight - size;
        el.pet.style.left = Math.max(0, Math.min(maxL, drag.baseLeft + dx)) + 'px';
        el.pet.style.top = Math.max(28, Math.min(maxT, drag.baseTop + dy)) + 'px';
      }
    });

    window.addEventListener('mouseup', () => {
      if (!drag.active) return;
      drag.active = false;
      const wasCarrying = machine._carrying;
      machine.pressEnd(performance.now() - drag.t0);
      if (native) post({ type: 'release', carried: wasCarrying });
      el.pet.classList.toggle('carrying', machine._carrying);
    });

    return { layoutHitboxes: layoutHitboxes, regionAt: regionAt };
  }

  root.Popo.createInput = createInput;
})(typeof globalThis !== 'undefined' ? globalThis : this);
