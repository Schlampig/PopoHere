/* PopoHere 原型 —— 状态机 + UI 装配。
   状态机部分是纯逻辑，不碰 DOM，之后可以 1:1 翻译成 Python。 */

/* ===================== ① 状态机 ===================== */
class PetStateMachine {
  constructor(theme, opts = {}) {
    this.theme = theme;
    this.beh = theme.behavior;
    this.state = 'idle';
    this.rand = opts.random || Math.random;
    this.paused = false;
    this.clock = 0;
    this.elapsed = 0;
    this.visual = null;
    this._press = null;
    this._carrying = false;
    this.prevPawAt = null;
    this.scratchCooldownUntil = 0;
    this._pickVisual();
  }

  get states() { return this.theme.states; }
  spec() { return this.states[this.state] || {}; }

  _pickVisual() {
    const vs = this.spec().visuals || [];
    this.visual = vs.length ? vs[Math.floor(this.rand() * vs.length)] : null;
  }

  _goto(next) {
    if (!this.states[next]) return;
    this.state = next;
    this.elapsed = 0;
    this._pickVisual();
  }

  /* ---- 时间推进：驱动 idle 分流 / menu 兜底 / 短时状态结束 ---- */
  tick(dt) {
    this.clock += dt;
    this.elapsed += dt;
    const st = this.spec();

    if (this.state === 'idle') {
      if (this.elapsed >= this.beh.idle_duration_sec) {
        this._goto(this.rand() < this.beh.walk_probability ? 'walk' : 'sleep');
      }
      return;
    }
    if (this.state === 'menu') {
      if (this.elapsed >= this.beh.menu_timeout_sec) this._goto('idle');
      return;
    }
    if (this.state === 'sleep' || this.state === 'dragging') return; // 等外部事件
    if (st.duration != null && this.elapsed >= st.duration) this._finish();
  }

  _finish() {
    switch (this.state) {
      case 'walk':
      case 'pet_head':
      case 'landed':
        this._goto('idle'); break;
      case 'pet_paw': {
        const cooling = this.clock < this.scratchCooldownUntil;
        this._goto(!cooling && (this._consecutivePaw || this.rand() < this.beh.scratch_probability) ? 'scratch' : 'idle');
        break;
      }
      case 'scratch':
        this.scratchCooldownUntil = this.clock + this.beh.scratch_cooldown_sec;
        this._goto('idle'); break;
      case 'startled':
        this._goto(this._carrying ? 'dragging' : 'idle'); break;
      default:
        this._goto('idle');
    }
  }

  /* ---- 鼠标 ---- */
  pressStart(region) {
    if (this.paused || this.state === 'menu') return;
    this._press = { region, dragging: false };
  }

  pressMove(distPx) {
    const p = this._press;
    if (!p || this.paused) return false;
    if (!p.dragging && distPx >= this.beh.click_max_drift_px) {
      p.dragging = true;
      this._carrying = true;
      this._goto(this.state === 'sleep' ? 'startled' : 'dragging'); // 睡中被抱起先惊醒
    }
    return this._carrying;
  }

  pressEnd(durationMs) {
    const p = this._press;
    this._press = null;
    if (!p) return;
    if (this.paused) { this._carrying = false; return; }
    if (p.dragging) {
      this._carrying = false;
      this._goto(this.states.landed ? 'landed' : 'idle');
      return;
    }
    if (durationMs > this.beh.click_max_duration_ms) return; // 长按不算单击
    this._click(p.region);
  }

  _click(region) {
    if (this.state === 'idle') {
      if (region === 'head') this._goto('pet_head');
      else if (region === 'paw') {
        // 与上一次摸脚的间隔在窗口内 = 连续摸脚
        this._consecutivePaw = this.prevPawAt !== null
          && (this.clock - this.prevPawAt) <= this.beh.repeat_paw_window_sec;
        this.prevPawAt = this.clock;
        this._goto('pet_paw');
      }
      else this.onBlankClick && this.onBlankClick();           // 小游戏钩子：目前什么都不做
    } else if (this.state === 'walk') {
      this._goto('idle');                                       // 走动中被点 → 打断
    } else if (this.state === 'sleep') {
      this._goto('startled');                                   // 唯一能进 startled 的路径
    }
  }

  openMenu() { if (this.state !== 'menu') this._goto('menu'); }
  closeMenu() { if (this.state === 'menu') this._goto('idle'); }
  force(state) { this._carrying = state === 'dragging'; this._goto(state); }
}


/* ===================== ② UI 装配 ===================== */
(function () {
  const NATIVE = (typeof POPO_NATIVE !== 'undefined' && POPO_NATIVE);
  const THEME = POPO_THEME;
  const BEH = THEME.behavior;
  function defaultPos() {
    return { left: 90, top: Math.max(40, window.innerHeight - petSize - 60) };
  }

  const el = {
    desktop: document.getElementById('desktop'),
    stage: document.getElementById('stage'),
    pet: document.getElementById('pet'),
    img: document.getElementById('petImg'),
    bubble: document.getElementById('bubble'),
    hbHead: document.getElementById('hbHead'),
    hbPaw: document.getElementById('hbPaw'),
    ctx: document.getElementById('ctx'),
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

  const machine = new PetStateMachine(THEME);
  let petSize = NATIVE ? Math.max(60, window.innerWidth - 16) : 230;

  /* 原生模式下通过 WKScriptMessageHandler 把消息发给 Objective-C 外壳 */
  function post(msg) {
    if (NATIVE && window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.popo) {
      window.webkit.messageHandlers.popo.postMessage(msg);
    }
  }
  let hidden = false;
  let lastFrame = performance.now();

  const logs = [];
  function log(msg) {
    logs.unshift(`${new Date().toLocaleTimeString('zh-CN', { hour12: false })} ${msg}`);
    logs.length = Math.min(logs.length, 5);
    el.log.innerHTML = logs.map(l => `<div>${l}</div>`).join('');
  }

  /* ---- 渲染 ---- */
  let renderedState = null;
  function render() {
    const st = machine.state;
    const spec = machine.spec();

    if (st !== renderedState) {
      log(`${renderedState || '—'} → ${st}`);
      renderedState = st;
      const url = POPO_IMAGES[machine.visual];
      if (url) el.img.src = url;
      const motion = spec.motion || 'none';
      el.img.className = 'm-' + motion;
      const b = spec.bubble;
      el.bubble.textContent = b || '';
      el.bubble.classList.toggle('on', !!b);
      el.bubble.classList.toggle('float', !!b);
      el.pet.classList.toggle('carrying', machine._carrying);
    }
    el.vState.textContent = st;
    el.vElapsed.textContent = machine.elapsed.toFixed(1) + 's';
    const cd = machine.scratchCooldownUntil - machine.clock;
    el.vCool.textContent = cd > 0 ? cd.toFixed(1) + 's' : '—';
    el.vPause.textContent = machine.paused ? '是' : '否';
  }

  /* ---- 主循环 ---- */
  function loop(now) {
    const dt = Math.min(0.25, (now - lastFrame) / 1000);
    lastFrame = now;
    const before = machine.state;
    machine.tick(dt);
    if (before !== machine.state) {
      // startled 期间仍在被抱着 → 保持 carrying 视觉
      el.pet.classList.toggle('carrying', machine._carrying);
    }
    render();
    requestAnimationFrame(loop);
  }
  requestAnimationFrame(loop);

  /* ---- hitbox ---- */
  function layoutHitboxes() {
    const bx = THEME.hitBoxes;
    for (const [name, node] of [['head', el.hbHead], ['paw', el.hbPaw]]) {
      const r = bx[name];
      node.style.left = r.x * petSize + 'px';
      node.style.top = r.y * petSize + 'px';
      node.style.width = r.w * petSize + 'px';
      node.style.height = r.h * petSize + 'px';
    }
  }

  function regionAt(offsetX, offsetY) {
    const bx = THEME.hitBoxes;
    const fx = offsetX / petSize, fy = offsetY / petSize;
    for (const name of ['head', 'paw']) {
      const r = bx[name];
      if (fx >= r.x && fx <= r.x + r.w && fy >= r.y && fy <= r.y + r.h) return name;
    }
    return 'blank';
  }

  /* ---- 拖拽 / 单击 ---- */
  const drag = { active: false, startX: 0, startY: 0, baseLeft: 0, baseTop: 0, dist: 0, t0: 0 };

  el.pet.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    drag.active = true;
    drag.dist = 0;
    drag.t0 = performance.now();
    // 一律用屏幕坐标算位移：原生模式下窗口会跟着光标移动，
    // 若用 clientX，视口随窗口漂移会让 delta 被抵消，既抖动又永远到不了拖拽阈值。
    drag.startX = e.screenX;
    drag.startY = e.screenY;
    const dp = defaultPos();
    drag.baseLeft = parseFloat(el.pet.style.left) ?? dp.left;
    drag.baseTop = parseFloat(el.pet.style.top) ?? dp.top;
    const rect = el.pet.getBoundingClientRect();
    drag.region = regionAt(e.clientX - rect.left, e.clientY - rect.top);
    machine.pressStart(drag.region);
    // 原生模式下只通知外壳"按下开始"，之后的位移由外壳用屏幕坐标跟踪，
    // 不在这里逐帧发包（网页坐标会被窗口自身的移动带偏，形成抖动反馈环）。
    if (NATIVE) post({ type: 'press' });
  });

  window.addEventListener('mousemove', (e) => {
    if (!drag.active) return;
    const dx = e.screenX - drag.startX, dy = e.screenY - drag.startY;
    drag.dist = Math.hypot(dx, dy);
    const carrying = machine.pressMove(drag.dist);   // 只推进状态机，不负责移动
    if (carrying && !NATIVE) {
      const maxL = el.stage.clientWidth - petSize;
      const maxT = el.stage.clientHeight - petSize;
      el.pet.style.left = Math.max(0, Math.min(maxL, drag.baseLeft + dx)) + 'px';
      el.pet.style.top = Math.max(28, Math.min(maxT, drag.baseTop + dy)) + 'px';
    }
  });

  window.addEventListener('mouseup', (e) => {
    if (!drag.active) return;
    drag.active = false;
    const wasCarrying = machine._carrying;
    machine.pressEnd(performance.now() - drag.t0);
    if (NATIVE) post({ type: 'release', carried: wasCarrying });
    el.pet.classList.toggle('carrying', machine._carrying);
  });

  /* ---- 右键菜单 ---- */
  el.desktop.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    if (machine.state === 'menu') return;
    machine.openMenu();
    el.ctx.classList.add('on');
    const r = el.ctx.getBoundingClientRect();
    el.ctx.style.left = Math.min(e.clientX, window.innerWidth - r.width - 8) + 'px';
    el.ctx.style.top = Math.min(e.clientY, window.innerHeight - r.height - 8) + 'px';
    syncMenu();
  });

  window.addEventListener('mousedown', (e) => {
    if (el.ctx.classList.contains('on') && !el.ctx.contains(e.target)) {
      el.ctx.classList.remove('on');
      machine.closeMenu();
    }
  }, true);

  function syncMenu() {
    document.querySelector('#mPause .state').textContent = machine.paused ? '是' : '否';
  }

  document.getElementById('mToggle').addEventListener('click', () => {
    hidden = !hidden; el.pet.classList.toggle('hidden', hidden);
    post({ type: 'hidden', value: hidden }); finishMenu();
  });
  document.getElementById('mPause').addEventListener('click', () => {
    machine.paused = !machine.paused; syncMenu();
    post({ type: 'paused', value: machine.paused }); finishMenu();
  });
  document.getElementById('mFolder').addEventListener('click', () => {
    post({ type: 'openTheme' }); finishMenu();
  });
  document.getElementById('mReset').addEventListener('click', () => { const dp = defaultPos(); setPos(dp.left, dp.top); finishMenu(); });
  document.getElementById('mQuit').addEventListener('click', () => { post({ type: 'quit' }); finishMenu(); });

  function finishMenu() {
    el.ctx.classList.remove('on');
    machine.closeMenu();
  }

  /* ---- 调试面板 ---- */
  const STATE_NAMES = ['idle', 'walk', 'sleep', 'pet_head', 'pet_paw', 'scratch', 'startled', 'dragging', 'landed', 'menu'];
  STATE_NAMES.forEach(s => {
    const b = document.createElement('button');
    b.textContent = s;
    b.addEventListener('click', () => machine.force(s));
    el.forceBtns.appendChild(b);
  });

  el.btnHB.addEventListener('click', () => {
    el.pet.classList.toggle('showHB');
    el.btnHB.classList.toggle('active', el.pet.classList.contains('showHB'));
  });

  function setPos(l, t) { el.pet.style.left = l + 'px'; el.pet.style.top = t + 'px'; }
  el.btnReset.addEventListener('click', () => { const dp = defaultPos(); setPos(dp.left, dp.top); });

  function setSize(px) {
    petSize = px;
    if (el.sizeVal) el.sizeVal.textContent = px;
    el.pet.style.width = px + 'px';
    el.pet.style.height = px + 'px';
    layoutHitboxes();
  }
  el.sizeSlider.addEventListener('input', (e) => setSize(parseInt(e.target.value, 10)));
  window.addEventListener('resize', () => { if (NATIVE) setSize(Math.max(60, window.innerWidth - 16)); });

  /* ---- 初始化 ---- */
  function fitInitial() {
    setSize(petSize);
    if (NATIVE) { setPos(8, 8); return; }
    const dp = defaultPos();
    setPos(dp.left, dp.top);
  }
  fitInitial();
  layoutHitboxes();
  render();
  if (!NATIVE) log('原型启动');

  /* 原生外壳（ns 菜单栏）通过这几个方法控制猫 */
  window.App = {
    setPaused: (v) => { machine.paused = !!v; },
    togglePaused: () => {
      machine.paused = !machine.paused;
      post({ type: 'paused', value: machine.paused });
      return machine.paused;
    },
    show: (v) => { hidden = !v; el.pet.classList.toggle('hidden', hidden); },
    setSize,
    force: (state) => machine.force(state),
    state: () => machine.state,
  };
  if (NATIVE) post({ type: 'ready' });
})();
