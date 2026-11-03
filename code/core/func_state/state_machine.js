/* PopoHere · 状态机（纯逻辑层）
 *
 * 职责
 *   把「时间流逝 + 鼠标事件」翻译成桌宠Popo的状态，并负责状态之间的流转规则。
 *   不接触 DOM、不接触窗口、不读取全局变量，只读取 theme.json 提供的参数。
 *
 * 状态集合
 *   常规：idle（静息）/ touch（被抚摸）/ scratch（不耐烦）/ play（自娱自乐）/
 *         sleep（睡眠）/ dragging（被拎起）/ menu（菜单待命）
 *   过渡：startled（惊醒）/ landed（落地）
 *
 * 两条核心不变量
 *   ① 所有「一次性状态播放完毕」都经由唯一出口 `_rest()` 决定去向：
 *      右键菜单面板确实开着则回到 menu，否则回到 idle。
 *      任何分支直接写 `_goto('idle')` 都会破坏「menu 状态与菜单面板同生共死」这一约束。
 *   ② `menuOpen` 描述的是外部事实（菜单面板是否真的显示在屏幕上），
 *      只由外壳在面板显示／收起时写入，状态机自身不推测。
 *
 * 参数倾向
 *   theme.json 的默认值按猫的习性调校（例如静息后更倾向睡觉、被反复抚摸会不耐烦）。
 *   若用于其它类型的桌宠，这些概率与阈值应重新评估。
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
      this.clock = 0;          // 单调累计秒数，用于冷却与间隔判定
      this.elapsed = 0;        // 当前状态已停留秒数
      this.visual = null;      // 当前使用的贴图文件名
      this.bubble = null;      // 当前气泡文案

      // 状态切换回调，供外壳同步窗口或面板（例如离开 menu 时收起菜单面板）
      this.onTransition = opts.onTransition || null;

      this._press = null;      // 本次按压的上下文 { region, dragging }
      this._carrying = false;  // 是否处于"被拎起"状态

      // 菜单面板是否确实显示在屏幕上；唯一事实来源，由外壳写入
      this.menuOpen = false;

      // 状态预览：在状态面板中点击状态名时置位，只播放一次，不参与任何计数
      this._previewing = false;

      // 连续抚摸计数：达到 touch_scratch_threshold 后转为不耐烦
      this.touchStreak = 0;
      this.prevTouchAt = null;
      this.scratchCooldownUntil = 0;

      this._pickVisual();
    }

    get states() { return this.theme.states; }
    get previewing() { return this._previewing; }

    spec() { return this.states[this.state] || {}; }

    /* 进入状态时等概率抽取一张贴图并锁定，离开后再次进入才重新抽取。
       气泡支持两种写法：bubble: "💤" 或 bubbles: ["❤️", "😌"]。 */
    _pickVisual() {
      const spec = this.spec();
      const visuals = spec.visuals || [];
      this.visual = visuals.length ? visuals[Math.floor(this.rand() * visuals.length)] : null;

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

    /* 一次性状态结束后的统一去向：菜单面板开着回 menu，否则回 idle。
       该出口保证「menu 状态」与「菜单面板」同时出现、同时消失。 */
    _rest() {
      this._previewing = false;
      this._goto(this.menuOpen ? 'menu' : 'idle');
    }

    /* 时间推进；dt 单位为秒 */
    tick(dt) {
      this.clock += dt;
      this.elapsed += dt;

      // 预览优先：到时长即走 _rest()，不触发连击、冷却等真实交互逻辑
      if (this._previewing) {
        const spec = this.spec();
        const limit = spec.duration != null ? spec.duration : this.beh.preview_duration_sec;
        if (this.elapsed >= limit) this._rest();
        return;
      }

      const spec = this.spec();

      if (this.state === 'idle') {
        // 菜单面板开着时不做自然流转，避免用户仍在操作菜单而桌宠已经走开
        if (this.menuOpen) return;
        if (this.elapsed >= this.beh.idle_duration_sec) {
          // 按猫的习性：多数时候选择趴下休息，少数时候继续活动
          const toPlay = this.rand() < this.beh.idle_to_play_probability;
          this._goto(toPlay ? 'play' : 'sleep');
        }
        return;
      }

      if (this.state === 'menu') {
        // menu 是等待外部事件的状态，不应自然入睡。
        // menu_timeout_sec 仅作为「面板未能正常关闭」的兜底；一旦触发即认为
        // 面板状态已不可信，同时清空 menuOpen，否则 _rest() 会重新落回 menu。
        if (this.elapsed >= this.beh.menu_timeout_sec) {
          this.menuOpen = false;
          this._goto('idle');
        }
        return;
      }

      if (this.state === 'sleep' || this.state === 'dragging') return;  // 等待外部事件
      if (spec.duration != null && this.elapsed >= spec.duration) this._finish();
    }

    _finish() {
      switch (this.state) {
        case 'touch': {
          // 常规路径在 _enterTouch 中已即时判定；此处兜住
          // 「冷却期内累计足够次数、而冷却结束时正好播放完毕」的情形。
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

        default:            // play / landed 等一次性状态
          this._rest();
      }
    }

    /* --- 鼠标交互 --- */

    pressStart(region) {
      // menu 状态下同样记录按压：此时点击桌宠的语义是收起菜单，不能被忽略
      this._press = { region, dragging: false };
    }

    /* 位移超过阈值即视为拖拽；返回是否处于"被拎起"状态 */
    pressMove(distPx) {
      const p = this._press;
      if (!p) return false;
      if (!p.dragging && distPx >= this.beh.click_max_drift_px) {
        p.dragging = true;
        this._carrying = true;
        this._previewing = false;                                     // 真实交互打断预览
        this._goto(this.state === 'sleep' ? 'startled' : 'dragging');  // 睡梦中被抱起先惊醒
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
      if (durationMs > this.beh.click_max_duration_ms) return;  // 长按不计为单击
      this._click();
    }

    /* 进入 touch 并累计连续抚摸次数。
       间隔以「进入时刻」为准计算（而非结束时刻），否则单次点击也会被计为连续。
       达到阈值时立即转入 scratch，而不是等本次 touch 播放完毕：
       每次点击都会重播 touch，等待播放结束将导致高频点击永远无法触发。 */
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
          // 点击桌宠即收起菜单并回到静息，使下一次点击恢复为正常互动
          this.closeMenu();
          break;

        case 'idle':
        case 'touch':
          // touch 播放中继续点击：重播并累计次数，
          // 否则连续十次点击只会被计为一次，不耐烦机制无法触发。
          this._enterTouch();
          break;

        case 'startled':
        case 'landed':
          // 两个过渡状态时长很短，用户连续点击时应继续计数，
          // 否则大部分点击会被过渡动画吞掉。
          this._enterTouch();
          break;

        case 'play':
          this._goto('idle');      // 自娱自乐被点击 → 打断
          break;

        case 'sleep':
          this._goto('startled');  // 进入 startled 的唯一路径
          break;

        default:
          break;                   // scratch 期间不响应点击
      }
    }

    /* 由外壳在菜单面板确实显示／收起时调用 */
    openMenu() {
      this.menuOpen = true;
      if (this.state !== 'menu') this._goto('menu');
    }

    closeMenu() {
      this.menuOpen = false;
      if (this.state === 'menu') this._goto('idle');
      // 预览中面板被关闭时不打断当前预览，播放结束后自然经 _rest() 回到 idle
    }

    /* 状态面板中点击状态名：只播放一次，不写入任何交互计数 */
    preview(state) {
      if (!this.states[state]) return;
      this._press = null;
      this._carrying = (state === 'dragging');
      this._previewing = true;
      this._goto(state);
    }

    /* 直接置位：仅供测试与内部诊断使用，不附加任何交互语义 */
    force(state) {
      this._previewing = false;
      this._carrying = state === 'dragging';
      this._goto(state);
    }
  }

  root.Popo.PetStateMachine = PetStateMachine;
})(typeof globalThis !== 'undefined' ? globalThis : this);
