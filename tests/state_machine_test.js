const fs=require('fs');
const R='/Users/pigpigbear/zyjProjects/Just_for_Fun/PopoHere/';
const app=fs.readFileSync(R+'prototype/src/app.js','utf8');
const machineSrc=app.split('/* ===================== ② UI')[0];
const THEME=JSON.parse(fs.readFileSync(R+'themes/popo/theme.json','utf8'));
const PetStateMachine=new Function(machineSrc+'; return PetStateMachine;')();

let pass=0,fail=0;
function eq(label,got,want){ if(got===want){pass++;} else {fail++; console.log(`FAIL ${label}: got ${got}, want ${want}`);} }
const mk=(r=0.5)=>new PetStateMachine(THEME,{random:()=>r});
const step=(m,sec,dt=0.1)=>{for(let t=0;t<sec;t+=dt)m.tick(dt);};
const click=(m,region)=>{m.pressStart(region);m.pressEnd(100);};
const drag=(m)=>{m.pressStart('head');return m.pressMove(10);};

// 1. idle 5s -> walk(rand<0.3) / sleep(rand>=0.3)
let m=mk(0.1); step(m,5.2); eq('idle->walk',m.state,'walk');
m=mk(0.9); step(m,5.2); eq('idle->sleep',m.state,'sleep');

// 2. walk 播完 -> idle
m=mk(0.1); step(m,5.2); step(m,2.6); eq('walk->idle',m.state,'idle');

// 3. idle 点脚 -> pet_paw -> idle(rand>=0.3 且不连续)
m=mk(0.9); click(m,'paw'); eq('idle点脚->pet_paw',m.state,'pet_paw'); step(m,1.1); eq('pet_paw->idle',m.state,'idle');

// 4. 3秒内连续摸脚 -> scratch
m=mk(0.9); click(m,'paw'); step(m,1.1); click(m,'paw'); step(m,1.1); eq('连续摸脚->scratch',m.state,'scratch');
// scratch 结束进冷却，冷却内摸脚不再挠
step(m,1.6); eq('scratch->idle',m.state,'idle');
click(m,'paw'); step(m,1.1); eq('冷却内摸脚->idle',m.state,'idle');

// 5. 睡觉被点 -> startled -> idle
m=mk(0.9); step(m,5.2); eq('sleep',m.state,'sleep'); click(m,'head'); eq('sleep被点->startled',m.state,'startled'); step(m,1.1); eq('startled->idle',m.state,'idle');

// 6. 睡中被拖 -> startled -> dragging -> 释放 -> landed -> idle
m=mk(0.9); step(m,5.2); let carrying=drag(m); eq('睡中拖->startled',m.state,'startled'); eq('拖=carrying',carrying,true);
step(m,1.1); eq('startled->dragging',m.state,'dragging');
m.pressEnd(100); eq('释放->landed',m.state,'landed'); step(m,0.9); eq('landed->idle',m.state,'idle');

// 7. idle 拖拽 -> dragging -> landed
m=mk(0.9); carrying=drag(m); eq('idle拖->dragging',m.state,'dragging'); m.pressEnd(100); eq('释放->landed',m.state,'landed');

// 8. 走动中被点 -> 打断回 idle
m=mk(0.1); step(m,5.2); click(m,'head'); eq('walk被点->idle',m.state,'idle');

// 9. idle 点头 -> pet_head -> idle
m=mk(0.9); click(m,'head'); eq('idle点头->pet_head',m.state,'pet_head'); step(m,1.6); eq('pet_head->idle',m.state,'idle');

// 10. 空白区：无响应
m=mk(0.9); let hook=0; m.onBlankClick=()=>hook++; click(m,'blank'); eq('空白区无切换',m.state,'idle'); eq('钩子被调用',hook,1);

// 11. 短时状态被点：忽略
m=mk(0.9); click(m,'head'); click(m,'paw'); eq('pet_head中点击忽略',m.state,'pet_head');

// 12. menu 状态 + 2s 兜底
m=mk(0.9); m.openMenu(); eq('openMenu',m.state,'menu'); click(m,'head'); eq('menu中点击忽略',m.state,'menu'); step(m,2.1); eq('menu兜底->idle',m.state,'idle');

// 13. 暂停互动：不响应点击和拖拽
m=mk(0.9); m.paused=true; click(m,'head'); eq('暂停点头无反应',m.state,'idle');
m.pressStart('head'); eq('暂停拖拽无反应',m.pressMove(20),false);

// 14. 长按不算单击
m=mk(0.9); m.pressStart('head'); m.pressEnd(500); eq('长按忽略',m.state,'idle');

// 15. 位移<5px 不算拖拽
m=mk(0.9); m.pressStart('head'); eq('小位移不拖',m.pressMove(3),false); m.pressEnd(50); eq('小位移=单击',m.state,'pet_head');

console.log(`\n通过 ${pass} / 失败 ${fail}`);
process.exit(fail?1:0);
