/* PopoHere · 入口
 *
 * 把状态机、渲染器、输入、菜单拼起来，跑主循环。
 * 这一层只做装配和全局状态（尺寸/位置/日志），具体逻辑都在 func_* 里。
 *
 * 依赖构建时注入的三个常量：POPO_THEME / POPO_IMAGES / POPO_NATIVE
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
    vPause: document.getElementById('vPause'),
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
      // 离开 menu 就一定让外壳把面板收掉。不能只依赖"面板失焦自己隐藏"：
      // 点猫时状态可能先走、面板还留在屏幕上，又变成两边不同步。
      // 例外是状态预览：菜单可以开着让用户逐个试状态，预览结束还会回 menu。
      if (from === 'menu' && to !== 'menu' && !machine.previewing) {
        post({ type: 'menuPanelClose' });
      }
    },
    onPausedClick: () => renderer.flashBubble('已暂停互动 · 菜单栏里可恢复', 1600),
  });

  let petSize = NATIVE ? Math.max(60, window.innerWidth - 16) : 230;
  let lastFrame = performance.now();

  /* 原生模式下把消息发给 Objective-C 外壳 */
  function post(msg) {
    if (NATIVE && window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.popo) {
      window.webkit.messageHandlers.popo.postMessage(msg);
    }
  }

  window.addEventListener('error', (e) => {
    post({ type: 'jserror', message: String(e.message) + ' @ ' + e.filename + ':' + e.lineno });
  });

  /* ---- 原型专用：日志 ---- */
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

  /* ---- 装配三大件 ---- */
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
    setPos: setPos,
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
    const dt = Math.min(0.25, (now - lastFrame) / 1000);
    lastFrame = now;
    machine.tick(dt);
    renderer.render();
    requestAnimationFrame(loop);
  }

  /* ---- 原型调试面板 ---- */
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
      // 原生窗口尺寸由外壳决定，窗口变化时把猫重新撑满
      window.addEventListener('resize', () => setSize(Math.max(60, window.innerWidth - 16)));
    } else {
      const dp = defaultPos();
      setPos(dp.left, dp.top);
      buildDebugPanel();
    }
    input.layoutHitboxes();
    renderer.render();
    if (!NATIVE) log('原型启动');
  }

  init();
  requestAnimationFrame(loop);

  /* 外壳（菜单栏）通过这些方法控制猫 */
  window.App = {
    setPaused: (v) => { machine.paused = !!v; },
    togglePaused: () => {
      machine.paused = !machine.paused;
      post({ type: 'paused', value: machine.paused });
      return machine.paused;
    },
    show: (v) => { el.pet.classList.toggle('hidden', !v); },
    notify: (text, ms) => renderer.flashBubble(text, ms),
    // 菜单状态由外壳唯一驱动：面板显示 → menuOpened()，面板收起 → menuClosed()
    menuOpened: () => machine.openMenu(),
    menuClosed: () => menu.notifyClosed(),
    setSize: setSize,
    force: (state) => machine.force(state),
    preview: (state) => machine.preview(state),
    state: () => machine.state,
    elapsed: () => machine.elapsed,
    streak: () => machine.touchStreak,
    threshold: () => BEH.touch_scratch_threshold,
    menuOpen: () => machine.menuOpen,
  };

  if (NATIVE) post({ type: 'ready' });
})();
