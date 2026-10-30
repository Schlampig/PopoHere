/* PopoHere · 渲染器
 *
 * 负责：状态 → 贴图 / 动效 class / 气泡，以及原型调试面板的数值回显。
 * 不负责：窗口、鼠标、状态流转。
 *
 * 对外暴露：Popo.createRenderer({ el, images, machine, onTransition })
 */
(function (root) {
  root.Popo = root.Popo || {};

  function createRenderer(opts) {
    const el = opts.el;
    const images = opts.images || {};
    const machine = opts.machine;
    const onTransition = opts.onTransition || function () {};

    let renderedState = null;
    let overrideBubble = null;      // 定时提醒等外部消息临时占用气泡
    let overrideUntil = 0;

    function paintPet() {
      const spec = machine.spec();
      const url = images[machine.visual];
      if (el.img && url) el.img.src = url;
      if (el.img) el.img.className = 'm-' + (spec.motion || 'none');

      const bubble = overrideBubble || machine.bubble;   // 外部消息优先
      if (el.bubble) {
        el.bubble.textContent = bubble || '';
        el.bubble.classList.toggle('on', !!bubble);
        el.bubble.classList.toggle('float', !!bubble);
      }
    }

    function paintDebug() {
      if (el.vState) el.vState.textContent = machine.state;
      if (el.vElapsed) el.vElapsed.textContent = machine.elapsed.toFixed(1) + 's';
      if (el.vCool) {
        const cd = machine.scratchCooldownUntil - machine.clock;
        el.vCool.textContent = cd > 0 ? cd.toFixed(1) + 's' : '—';
      }
    }

    function flashBubble(text, ms) {
      overrideBubble = text;
      overrideUntil = performance.now() + (ms || 4000);
      if (el.bubble) {
        el.bubble.textContent = text;
        el.bubble.classList.add('on');
        el.bubble.classList.remove('float');
      }
    }

    function render() {
      if (overrideBubble && performance.now() > overrideUntil) {
        overrideBubble = null;
        renderedState = null;      // 逼下一帧重画气泡
      }
      const st = machine.state;
      if (st !== renderedState) {
        onTransition(renderedState, st);
        renderedState = st;
        paintPet();
      }
      // carrying 会在同一状态内变化（例如 startled 播放期间仍被抱着），每帧同步一次最省心
      if (el.pet) el.pet.classList.toggle('carrying', !!machine._carrying);
      paintDebug();
    }

    return { render: render, flashBubble: flashBubble };
  }

  root.Popo.createRenderer = createRenderer;
})(typeof globalThis !== 'undefined' ? globalThis : this);
