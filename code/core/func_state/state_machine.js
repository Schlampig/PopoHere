/* PopoHere · 状态机（纯逻辑）
 *
 * 这一层刻意不碰 DOM、不碰窗口、不读全局变量，只吃 theme 数据、吐状态。
 * 好处：可以被 Node 直接跑单元测试，也可以原样翻译成别的语言。
 *
 * 状态：idle / touch / scratch / play / sleep / dragging / menu + startled / landed
 *
 * 两条不变量（改动前务必读懂）：
 *   ① 任何"播放结束"的落点只有一个出口 `_rest()`：
 *      右键菜单开着就回 menu，否则回 idle。
 *      以前各处直接写 _goto('idle')，于是面板还开着猫已经在 idle 起步了。
 *   ② `menuOpen` 是外部事实（面板真的在屏幕上），只在面板显示/收起时由外壳写入。
 *
 * 对外暴露：Popo.PetStateMachine
 */
(function (root) {
  root.Popo = root.Popo || {};

  class PetStateMachine {
    constructor(theme, opts = {}) {
      this.theme = theme;
      this.beh = theme.behavior;
      this.state = 'idle';
      this.rand = opts.random || Math.random;
      this.clock = 0;
      this.elapsed = 0;
      this.visual = null;
      this.bubble = null;

      // 状态切换回调：给外壳用（例如离开 menu 就必须把菜单面板收掉）
      this.onTransition = opts.onTransition || null;

      this._press = null;
      this._carrying = false;

      // 右键菜单是否真的开着（由外壳在面板显示/收起时写入，是唯一真相）
      this.menuOpen = false;

      // 状态预览（状态面板里点状态名）：只负责演，不参与连击、不写任何计数器
      this._previewing = false;

      // 连撸计数：连续 touch_scratch_threshold 次就翻脸
      this.touchStreak = 0;
      this.prevTouchAt = null;
      this.scratchCooldownUntil = 0;

      this._pickVisual();
    }

    get states() { return this.theme.states; }
    get previewing() { return this._previewing; }
    get previewing() { return this._previewing; }
    spec() { return this.states[this.state] || {}; }

    _pickVisual() {
      const spec = this.spec();
      const visuals = spec.visuals || [];
      this.visual = visuals.length ? visuals[Math.floor(this.rand() * visuals.length)] : null;

      // 气泡支持两种写法：bubble:"💤" 或 bubbles:["❤️","😌"]（进入状态时随机一个）
      const bubbles = spec.bubbles || (spec.bubble ? [spec.bubble] : []);
      this.bubble = bubbles.length ? bubbles[Math.floor(this.rand() * bubbles.length)] : null;
    }

    _goto(next) {
      if (!this.states[next]) return;
      const from = this.state;
      this.state = next;
      this.elapsed = 0;
      this._pickVisual();
      if (from !== next && this.onTransition) this.onTransition(from, next);
    }

    /* 唯一的"播完了去哪"出口：菜单还开着就回 menu，否则回 idle。
       这一条保证了「menu 状态 ⟺ 右键菜单面板」始终同时存在、同时消失。 */
    _rest() {
      this._previewing = false;
      this._goto(this.menuOpen ? 'menu' : 'idle');
    }

    /* 时间推进 */
    tick(dt) {
      this.clock += dt;
      this.elapsed += dt;

      // 预览优先：到点就回到 _rest()，不触发 touch→scratch 之类的真实逻辑
      if (this._previewing) {
        const spec = this.spec();
        const limit = spec.duration != null ? spec.duration : this.beh.preview_duration_sec;
        if (this.elapsed >= limit) this._rest();
        return;
      }

      const spec = this.spec();

      if (this.state === 'idle') {
        // 菜单开着时猫不会自己溜达/睡着——它得等用户把菜单看完
        if (this.menuOpen) return;
        if (this.elapsed >= this.beh.idle_duration_sec) {
          // 猫的天性：更多时候是趴下睡觉，而不是继续玩
          const toPlay = this.rand() < this.beh.idle_to_play_probability;
          this._goto(toPlay ? 'play' : 'sleep');
        }
        return;
      }
      if (this.state === 'menu') {
        // 菜单开着时不允许自然入睡（否则用户还在设置里，猫已经睡了）。
        // 这个超时只是"面板没关成功"的兜底，值给得很大；真触发时说明面板状态
        // 已经不可信，直接当作关闭，否则 _rest() 会又回到 menu，永远出不来。
        if (this.elapsed >= this.beh.menu_timeout_sec) {
          this.menuOpen = false;
          this._goto('idle');
        }
        return;
      }
      if (this.state === 'sleep' || this.state === 'dragging') return;  // 等外部事件
      if (spec.duration != null && this.elapsed >= spec.duration) this._finish();
    }

    _finish() {
      switch (this.state) {
        case 'touch': {
          // 正常路径下阈值在 _enterTouch 里就立刻翻脸了；
          // 这里兜住"冷却期内连点够数、冷却结束时正好播完"的情况。
          const cooling = this.clock < this.scratchCooldownUntil;
          if (!cooling && this.touchStreak >= this.beh.touch_scratch_threshold) {
            this._goto('scratch');
          } else {
            this._rest();
          }
          break;
        }

        case 'scratch':
          this.scratchCooldownUntil = this.clock + this.beh.scratch_cooldown_sec;
          this.touchStreak = 0;
          this.prevTouchAt = null;
          this._rest();
          break;

        case 'startled':
          if (this._carrying) {
            this._goto('dragging');
          } else {
            this._rest();
          }
          break;

        default:            // play / landed / 其它一次性状态
          this._rest();
      }
    }

    /* --- 鼠标 --- */
    pressStart(region) {
      // menu 状态也要记录按压：面板开着时点猫 = 关掉面板，不能把这一下吞掉
      this._press = { region, dragging: false };
    }

    pressMove(distPx) {
      const p = this._press;
      if (!p) return false;
      if (!p.dragging && distPx >= this.beh.click_max_drift_px) {
        p.dragging = true;
        this._carrying = true;
        this._previewing = false;                                   // 真互动打断预览
        this._goto(this.state === 'sleep' ? 'startled' : 'dragging');  // 睡中被抱起先惊醒
      }
      return this._carrying;
    }

    pressEnd(durationMs) {
      const p = this._press;
      this._press = null;
      if (!p) return;

      if (p.dragging) {
        this._carrying = false;
        this._goto(this.states.landed ? 'landed' : 'idle');
        return;
      }
      if (durationMs > this.beh.click_max_duration_ms) return;  // 长按不算单击
      this._click();
    }

    /* 进入 touch，并累计连撸次数。
       在"进入的那一刻"计算间隔，不能在结束时算——v1.0 在这里踩过坑。
       够数就**当场**翻脸，不等 touch 播完：否则越使劲点越看不到挠人
       （每一下都会重播 touch，永远走不到结束）。 */
    _enterTouch() {
      const win = this.beh.touch_repeat_window_sec;
      const continuing = this.prevTouchAt !== null && (this.clock - this.prevTouchAt) <= win;
      this.touchStreak = continuing ? this.touchStreak + 1 : 1;
      this.prevTouchAt = this.clock;

      const cooling = this.clock < this.scratchCooldownUntil;
      if (!cooling && this.touchStreak >= this.beh.touch_scratch_threshold) {
        this._goto('scratch');
        return;
      }
      this._goto('touch');
    }

    _click() {
      switch (this.state) {
        case 'menu':
          // 点猫即收起菜单并回到静息，下一次点击就能正常互动
          this.closeMenu();
          break;

        case 'idle':
        case 'touch':
          // 撸到一半还在点 → 重新播一遍，连击 +1。
          // 否则"连点 10 下"会被吞成 1 下，翻脸机制永远触发不了。
          this._enterTouch();
          break;

        case 'startled':
        case 'landed':
          // 惊醒 / 落地这两个过渡态很短，用户正在兴头上狂点时必须继续计数，
          // 否则一轮猛点会被过渡动画吃掉大半（这是"点十几下没反应"的主因之一）。
          this._enterTouch();
          break;

        case 'play':
          this._goto('idle');      // 玩到一半被点 → 打断
          break;

        case 'sleep':
          this._goto('startled');  // 唯一能进 startled 的路径
          break;

        default:
          break;                   // scratch 时点击无响应（正在生气，别理你）
      }
    }

    /* 外壳在面板真的显示/收起时调用 */
    openMenu() {
      this.menuOpen = true;
      if (this.state !== 'menu') this._goto('menu');
    }

    closeMenu() {
      this.menuOpen = false;
      if (this.state === 'menu') this._goto('idle');
      // 预览中面板被关掉：不打断当前预览，播完自然会走 _rest() → idle
    }

    /* 状态面板里点状态名：只演一遍，不写计数器 */
    preview(state) {
      if (!this.states[state]) return;
      this._press = null;
      this._carrying = (state === 'dragging');
      this._previewing = true;
      this._goto(state);
    }

    /* 直接置位：给测试和 QA 用，不做任何附加语义 */
    force(state) {
      this._previewing = false;
      this._carrying = state === 'dragging';
      this._goto(state);
    }
  }

  root.Popo.PetStateMachine = PetStateMachine;
})(typeof globalThis !== 'undefined' ? globalThis : this);
