/* PopoHere · 状态机（纯逻辑）
 *
 * 这一层刻意不碰 DOM、不碰窗口、不读全局变量，只吃 theme 数据、吐状态。
 * 好处：可以被 Node 直接跑单元测试，也可以原样翻译成别的语言。
 *
 * 状态：idle / touch / scratch / play / sleep / dragging / menu + startled / landed
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
      this.paused = false;
      this.clock = 0;
      this.elapsed = 0;
      this.visual = null;
      this.bubble = null;

      this._press = null;
      this._carrying = false;

      // 连撸计数：连续 10 次就翻脸
      this.touchStreak = 0;
      this.prevTouchAt = null;
      this.scratchCooldownUntil = 0;

      this._pickVisual();
    }

    get states() { return this.theme.states; }
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
      this.state = next;
      this.elapsed = 0;
      this._pickVisual();
    }

    /* 时间推进：idle 分流 / menu 兜底 / 短时状态结束 */
    tick(dt) {
      this.clock += dt;
      this.elapsed += dt;
      const spec = this.spec();

      if (this.state === 'idle') {
        if (this.elapsed >= this.beh.idle_duration_sec) {
          // 猫的天性：更多时候是趴下睡觉，而不是继续玩
          const toPlay = this.rand() < this.beh.idle_to_play_probability;
          this._goto(toPlay ? 'play' : 'sleep');
        }
        return;
      }
      if (this.state === 'menu') {
        if (this.elapsed >= this.beh.menu_timeout_sec) this._goto('idle');
        return;
      }
      if (this.state === 'sleep' || this.state === 'dragging') return;  // 等外部事件
      if (spec.duration != null && this.elapsed >= spec.duration) this._finish();
    }

    _finish() {
      switch (this.state) {
        case 'play':
        case 'landed':
          this._goto('idle'); break;

        case 'touch': {
          const cooling = this.clock < this.scratchCooldownUntil;
          if (!cooling && this.touchStreak >= this.beh.touch_scratch_threshold) {
            this._goto('scratch');
          } else {
            this._goto('idle');
          }
          break;
        }

        case 'scratch':
          this.scratchCooldownUntil = this.clock + this.beh.scratch_cooldown_sec;
          this.touchStreak = 0;
          this.prevTouchAt = null;
          this._goto('idle');
          break;

        case 'startled':
          this._goto(this._carrying ? 'dragging' : 'idle'); break;

        default:
          this._goto('idle');
      }
    }

    /* --- 鼠标 --- */
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
        this._goto(this.state === 'sleep' ? 'startled' : 'dragging');  // 睡中被抱起先惊醒
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
      if (durationMs > this.beh.click_max_duration_ms) return;  // 长按不算单击
      this._click();
    }

    /* 进入 touch，并累计连撸次数。
       在"进入的那一刻"计算间隔，不能在结束时算——v1.0 在这里踩过坑。 */
    _enterTouch() {
      const window = this.beh.touch_repeat_window_sec;
      const continuing = this.prevTouchAt !== null && (this.clock - this.prevTouchAt) <= window;
      this.touchStreak = continuing ? this.touchStreak + 1 : 1;
      this.prevTouchAt = this.clock;
      this._goto('touch');
    }

    _click() {
      switch (this.state) {
        case 'idle':
          this._enterTouch();
          break;
        case 'touch':
          // 撸到一半还在点 → 重新播一遍，连击 +1。
          // 否则"连点 10 下"会被吞成 1 下，翻脸机制永远触发不了。
          this._enterTouch();
          break;
        case 'play':
          this._goto('idle');      // 玩到一半被点 → 打断
          break;
        case 'sleep':
          this._goto('startled');  // 唯一能进 startled 的路径
          break;
        default:
          break;                   // scratch / startled / landed 时点击无响应
      }
    }

    openMenu() { if (this.state !== 'menu') this._goto('menu'); }
    closeMenu() { if (this.state === 'menu') this._goto('idle'); }
    force(state) { this._carrying = state === 'dragging'; this._goto(state); }
  }

  root.Popo.PetStateMachine = PetStateMachine;
})(typeof globalThis !== 'undefined' ? globalThis : this);
