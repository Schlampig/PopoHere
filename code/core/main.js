/* PopoHere · 页面入口
 *
 * 职责
 *   装配状态机、渲染层、输入层与菜单桥，并驱动主循环（requestAnimationFrame）。
 *   同时把尺寸、位置、调试面板等页面级状态收敛在这一层，供各模块回调。
 *   具体行为逻辑位于 func_state / func_render / func_input / func_menu。
 *
 * 两种运行模式
 *   POPO_NATIVE 为真：页面运行在 .app 的 WKWebView 内，窗口由外壳管理，
 *                     这里只负责把事件与状态同步给外壳。
 *   POPO_NATIVE 为假：浏览器预览模式，页面自己摆放桌宠并显示调试面板。
 *
 * 构建期注入的常量
 *   POPO_THEME（状态与行为参数）、POPO_IMAGES（贴图 data URI）、POPO_NATIVE（运行模式）
 */
(function () {
  const NATIVE = (typeof POPO_NATIVE !== 'undefined') && POPO_NATIVE;
  const THEME = POPO_THEME;
  const IMAGES = POPO_IMAGES;

  const el = {
    desktop: document.getElementById('desktop'),
    stage: document.getElementById('stage'),
    pet: document.getElementById('pet'),
    img: document.getElementById('petImg'),
    bubble: document.getElementById('bubble'),
    hbBody: document.getElementById('hbBody'),
    vState: document.getElementById('vState'),
    vElapsed: document.getElementById('vElapsed'),
    vCool: document.getElementById('vCool'),
    log: document.getElementById('log'),
    forceBtns: document.getElementById('forceBtns'),
    btnHB: document.getElementById('btnHB'),
    btnReset: document.getElementById('btnReset'),
    sizeSlider: document.getElementById('sizeSlider'),
    sizeVal: document.getElementById('sizeVal'),
  };

  if (NATIVE) document.body.classList.add('native');

  const machine = new Popo.PetStateMachine(THEME, {
    onTransition: (from, to) => {
      // 离开 menu 时同步收起菜单面板：状态切换可能先于面板收起发生，
      // 仅依赖面板失焦自动隐藏会造成状态与面板不一致。
      // 状态预览是例外——菜单保持打开，便于用户逐个查看状态。
      if (from === 'menu' && to !== 'menu' && !machine.previewing) {
        post({ type: 'menuPanelClose' });
      }
    },
  });

  let petSize = NATIVE ? Math.max(60, window.innerWidth - 16) : 230;
  let lastFrame = performance.now();

  /* 原生模式下向 Objective-C 外壳发送消息 */
  function post(msg) {
    if (NATIVE && window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.popo) {
      window.webkit.messageHandlers.popo.postMessage(msg);
    }
  }

  window.addEventListener('error', (e) => {
    post({ type: 'jserror', message: String(e.message) + ' @ ' + e.filename + ':' + e.lineno });
  });

  /* ---- 浏览器预览专用：日志 ---- */
  const logs = [];
  function log(msg) {
    if (!el.log) return;
    logs.unshift(`${new Date().toLocaleTimeString('zh-CN', { hour12: false })} ${msg}`);
    logs.length = Math.min(logs.length, 5);
    el.log.innerHTML = logs.map((l) => `<div>${l}</div>`).join('');
  }

  function defaultPos() {
    return { left: 90, top: Math.max(40, window.innerHeight - petSize - 60) };
  }

  function setPos(left, top) {
    el.pet.style.left = left + 'px';
    el.pet.style.top = top + 'px';
  }

  /* ---- 装配各功能模块 ---- */
  const renderer = Popo.createRenderer({
    el: el,
    images: IMAGES,
    machine: machine,
    onTransition: (from, to) => {
      if (!NATIVE) log(`${from || '—'} → ${to}`);
    },
  });

  const input = Popo.createInput({
    el: el,
    theme: THEME,
    machine: machine,
    native: NATIVE,
    post: post,
    getSize: () => petSize,
    getDefaultPos: defaultPos,
  });

  const menu = Popo.createMenu({
    el: el,
    machine: machine,
    post: post,
    native: NATIVE,
    log: log,
  });

  function setSize(px) {
    petSize = px;
    if (el.sizeVal) el.sizeVal.textContent = px;
    el.pet.style.width = px + 'px';
    el.pet.style.height = px + 'px';
    input.layoutHitboxes();
  }

  /* ---- 主循环 ---- */
  function loop(now) {
    // 步长限制在 [0, 0.25] 秒：
    //   上限避免窗口被挂起或标签页切回时一次性推进过多；
    //   下限避免首帧 rAF 时间戳早于初始化时刻，产生负值时把单调时钟推成负数，
    //   进而使冷却判定把「尚未开始冷却」误判为「正在冷却」。
    const dt = Math.min(0.25, Math.max(0, (now - lastFrame) / 1000));
    lastFrame = now;
    machine.tick(dt);
    renderer.render();
    requestAnimationFrame(loop);
  }

  /* ---- 浏览器预览专用：调试面板 ---- */
  function buildDebugPanel() {
    if (el.forceBtns) {
      Object.keys(THEME.states).forEach((name) => {
        const b = document.createElement('button');
        b.textContent = name;
        b.addEventListener('click', () => machine.force(name));
        el.forceBtns.appendChild(b);
      });
    }
    if (el.btnHB) {
      el.btnHB.addEventListener('click', () => {
        el.pet.classList.toggle('showHB');
        el.btnHB.classList.toggle('active', el.pet.classList.contains('showHB'));
      });
    }
    if (el.btnReset) {
      el.btnReset.addEventListener('click', () => {
        const dp = defaultPos();
        setPos(dp.left, dp.top);
      });
    }
    if (el.sizeSlider) {
      el.sizeSlider.addEventListener('input', (e) => setSize(parseInt(e.target.value, 10)));
    }
  }

  /* ---- 初始化 ---- */
  function init() {
    setSize(petSize);
    if (NATIVE) {
      setPos(8, 8);
      // 原生窗口尺寸由外壳决定；窗口变化时让贴图重新铺满
      window.addEventListener('resize', () => setSize(Math.max(60, window.innerWidth - 16)));
    } else {
      const dp = defaultPos();
      setPos(dp.left, dp.top);
      buildDebugPanel();
    }
    input.layoutHitboxes();
    renderer.render();
    if (!NATIVE) log('预览启动');
  }

  init();
  requestAnimationFrame(loop);

  /* 外壳通过以下接口控制桌宠与读取运行状态 */
  window.App = {
    show: (v) => { el.pet.classList.toggle('hidden', !v); },
    notify: (text, ms) => renderer.flashBubble(text, ms),
    // menu 状态由外壳单向驱动：面板显示 → menuOpened()，面板收起 → menuClosed()
    menuOpened: () => machine.openMenu(),
    menuClosed: () => menu.notifyClosed(),
    setSize: setSize,
    force: (state) => machine.force(state),
    preview: (state) => machine.preview(state),
    state: () => machine.state,
    elapsed: () => machine.elapsed,
    streak: () => machine.touchStreak,
    threshold: () => THEME.behavior.touch_scratch_threshold,
    menuOpen: () => machine.menuOpen,
  };

  if (NATIVE) post({ type: 'ready' });
})();
