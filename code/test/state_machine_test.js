/* 状态机单元测试（v2.0）
 *
 *   node code/test/state_machine_test.js
 *
 * 纯逻辑测试：不依赖 DOM、不依赖浏览器。
 */
const fs = require('fs');
const path = require('path');

const CODE = path.dirname(path.dirname(path.resolve(__filename)));   // code/
const SRC = path.join(CODE, 'core', 'func_state', 'state_machine.js');
const THEME = JSON.parse(fs.readFileSync(path.join(CODE, 'pet_images', 'theme.json'), 'utf8'));

// 模块用 globalThis 当根对象。这里塞一个假 globalThis 进去做隔离，不污染真全局。
const sandbox = {};
new Function('globalThis', fs.readFileSync(SRC, 'utf8'))(sandbox);
const PetStateMachine = sandbox.Popo.PetStateMachine;

let pass = 0, fail = 0;
function eq(label, got, want) {
  if (got === want) { pass++; }
  else { fail++; console.log(`FAIL ${label}: got ${got}, want ${want}`); }
}

const mk = (r = 0.5) => new PetStateMachine(THEME, { random: () => r });
const step = (m, sec, dt = 0.1) => { for (let t = 0; t < sec; t += dt) m.tick(dt); };
const click = (m) => { m.pressStart('body'); m.pressEnd(100); };
const rapid = (m, n) => { for (let i = 0; i < n; i++) click(m); };
const drag = (m) => { m.pressStart('body'); return m.pressMove(10); };

const BEH = THEME.behavior;

/* ---- 1. idle 分流 ---- */
// random 固定 0.1 < 0.35 → play
let m = mk(0.1);
step(m, 5.2);
eq('idle 满 5s → play', m.state, 'play');

// random 固定 0.9 > 0.35 → sleep
m = mk(0.9);
step(m, 5.2);
eq('idle 满 5s → sleep', m.state, 'sleep');

/* ---- 2. play 播完回 idle ---- */
m = mk(0.1);
step(m, 5.2);
step(m, 2.6);
eq('play 播完 → idle', m.state, 'idle');

/* ---- 3. 单击进入 touch ---- */
m = mk(0.9);
click(m);
eq('idle 单击 → touch', m.state, 'touch');

/* ---- 4. touch 播完回 idle（未达阈值） ---- */
step(m, 1.6);
eq('touch 播完 → idle', m.state, 'idle');
eq('连撸计数为 1', m.touchStreak, 1);

/* ---- 5. 连撸 9 次还不翻脸 ---- */
m = mk(0.9);
rapid(m, 9);
eq('连点 9 次仍停在 touch', m.state, 'touch');
eq('连撸计数 9', m.touchStreak, 9);
step(m, 1.6);
eq('9 次未达阈值 → idle', m.state, 'idle');

/* ---- 6. 第 10 次翻脸 ---- */
rapid(m, 1);                       // 第 10 次（间隔仍在窗口内）
eq('第 10 次进入 touch', m.touchStreak, 10);
step(m, 1.6);
eq('10 次达阈值 → scratch', m.state, 'scratch');

/* ---- 7. scratch 结束进冷却，冷却期内不再翻脸 ---- */
step(m, 1.6);
eq('scratch 播完 → idle', m.state, 'idle');
eq('连撸计数已清零', m.touchStreak, 0);
rapid(m, 12);                      // 冷却期内疯狂点
step(m, 1.6);
eq('冷却期内连点不翻脸', m.state, 'idle');

// 冷却过去后再点 10 次，恢复翻脸
step(m, BEH.scratch_cooldown_sec + 0.5);
m.force('idle');                   // 这段时间里猫可能已经睡着了，先拉回 idle
rapid(m, 10);
step(m, 1.6);
eq('冷却结束后可再次翻脸', m.state, 'scratch');

/* ---- 8. 睡中被点 → startled → idle ---- */
m = mk(0.9);
step(m, 5.2);
eq('已入睡', m.state, 'sleep');
click(m);
eq('睡中被点 → startled', m.state, 'startled');
step(m, 1.1);
eq('startled 播完 → idle', m.state, 'idle');

/* ---- 9. 睡中被拖 → startled → dragging → 释放 → landed ---- */
m = mk(0.9);
step(m, 5.2);
drag(m);
eq('睡中被拖 → startled', m.state, 'startled');
step(m, 1.1);
eq('手还按着 → dragging', m.state, 'dragging');
m.pressEnd(100);
eq('释放 → landed', m.state, 'landed');
step(m, 0.9);
eq('landed 播完 → idle', m.state, 'idle');

/* ---- 10. 玩到一半被点只是打断，不进入 touch ---- */
m = mk(0.1);
step(m, 5.2);
eq('处于 play', m.state, 'play');
click(m);
eq('play 中点击 → idle', m.state, 'idle');

/* ---- 11. menu 状态 ---- */
m = mk(0.9);
m.openMenu();
eq('openMenu → menu', m.state, 'menu');
step(m, 10);
eq('菜单开着 10s 不会自己睡着', m.state, 'menu');
click(m);
eq('点猫收起菜单 → idle', m.state, 'idle');

// 兜底：面板万一没关成功，超时也要能回到 idle
m.openMenu();
step(m, BEH.menu_timeout_sec + 0.5);
eq('兜底超时 → idle', m.state, 'idle');

/* ---- 12. 暂停互动 ---- */
m = mk(0.9);
m.paused = true;
click(m);
eq('暂停时点击无反应', m.state, 'idle');
m.pressStart('body');
eq('暂停时拖拽无反应', m.pressMove(30), false);

/* ---- 13. 长按不算单击 ---- */
m = mk(0.9);
m.pressStart('body');
m.pressEnd(500);
eq('长按不触发 touch', m.state, 'idle');

/* ---- 14. 微小位移仍算单击 ---- */
m = mk(0.9);
m.pressStart('body');
eq('3px 不算拖拽', m.pressMove(3), false);
m.pressEnd(50);
eq('微小位移 = 单击', m.state, 'touch');

/* ---- 15. 视觉与气泡从当前状态的素材池里取 ---- */
m = mk(0.9);
click(m);
eq('视觉来自 touch 素材池', THEME.states.touch.visuals.includes(m.visual), true);
eq('气泡来自 touch 气泡池', THEME.states.touch.bubbles.includes(m.bubble), true);

m = mk(0.9);
step(m, 5.2);
eq('睡眠气泡为 💤', m.bubble, '💤');

/* ---- 16. 缺失状态的容错 ---- */
m = mk(0.9);
m.force('不存在的状态');
eq('force 到未知状态被忽略', m.state, 'idle');

console.log(`\n通过 ${pass} / 失败 ${fail}`);
process.exit(fail ? 1 : 0);
