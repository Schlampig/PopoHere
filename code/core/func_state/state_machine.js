/* PopoHere · 状态机（纯逻辑）
 *
 * 这一层刻意不碰 DOM、不碰窗口、不读全局变量，只吃 theme 数据、吐状态。
 * 好处：可以被 Node 直接跑单元测试，也可以原样翻译成别的语言。
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

    /* 时间推进：驱动 idle 分流 / menu 兜底 / 短时状态结束 */
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
          this._goto(!cooling && (this._consecutivePaw || this.rand() < this.beh.scratch_probability)
            ? 'scratch' : 'idle');
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
        } else if (this.onBlankClick) {
          this.onBlankClick();            // 空白区钩子：留给以后的小游戏
        }
      } else if (this.state === 'walk') {
        this._goto('idle');               // 走动中被点 → 打断
      } else if (this.state === 'sleep') {
        this._goto('startled');           // 唯一能进 startled 的路径
      }
    }

    openMenu() { if (this.state !== 'menu') this._goto('menu'); }
    closeMenu() { if (this.state === 'menu') this._goto('idle'); }
    force(state) { this._carrying = state === 'dragging'; this._goto(state); }
  }

  root.Popo.PetStateMachine = PetStateMachine;
})(typeof globalThis !== 'undefined' ? globalThis : this);
