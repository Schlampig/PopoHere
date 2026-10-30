"""拖拽判定回归测试。

背景（2026-10-28 修）：
早期实现里 JS 用 e.clientX 算拖拽位移，而窗口本身会跟着光标移动 —— 承载页面的视口
一漂移，clientX 就被拉回原点，delta 被抵消。后果有两个：① 窗口抖动/发飘；② 位移永远
到不了阈值，状态机进不了 dragging。修复方式是 JS 与原生外壳都统一用屏幕坐标推算位移。

本测试直接对 prototype/index.html 派发合成鼠标事件，并刻意构造"clientX 纹丝不动、
只有 screenX 递增"的场景（即窗口跟随后视口的真实表现），断言状态机仍正确判定为拖拽。

用法：
    python3 code/build/build_web.py && python3 code/test/drag_tracking_test.py
"""

from __future__ import annotations

import html
import os
import re
import subprocess
import sys
import tempfile

CODE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # code/
PREVIEW = os.path.join(CODE, "build", "out", "preview.html")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

DRIVER = r"""
window.addEventListener('error', e => report([], String(e.message)));

function report(out, errNote) {
  if (errNote) out.unshift('FAIL 测试脚本自身异常 | got=' + errNote + ' want=正常运行');
  const pre = document.createElement('pre');
  pre.textContent = '\n' + out.join('\n') + '\n';   // 首尾换行，方便外部按行提取
  document.body.appendChild(pre);
}

try {
  const out = [];
  const ok = (l, got, want) => out.push((got === want ? 'PASS' : 'FAIL') +
      ' ' + l + ' | got=' + got + ' want=' + want);
  // 无头模式下页面被视为后台，tick/render 定时器被节流，
  // 所以一律直接读 App.state()，不依赖调试面板的文字。
  const S = () => window.App.state();
  const ev = (type, cx, cy, sx, sy) => new MouseEvent(type, {
      bubbles: true, cancelable: true, button: 0, clientX: cx, clientY: cy,
      screenX: sx, screenY: sy });

  const pet = document.getElementById('pet');
  const r = pet.getBoundingClientRect();
  const ax = Math.round(r.left + r.width / 2), ay = Math.round(r.top + r.height / 2);

  ok('起始状态', S(), 'idle');
  const before = parseFloat(pet.style.left);

  pet.dispatchEvent(ev('mousedown', ax, ay, 500, 500));
  ok('按下后仍是 idle', S(), 'idle');

  // 核心：clientX 保持不动，只有 screenX 递增 —— 模拟窗口跟着光标走时的视口表现
  window.dispatchEvent(ev('mousemove', ax, ay, 512, 500));
  ok('视口跟随后仍能越过阈值 -> dragging', S(), 'dragging');

  window.dispatchEvent(ev('mousemove', ax, ay, 560, 500));
  ok('继续拖动保持 dragging', S(), 'dragging');
  ok('元素位移等于光标位移',
     (parseFloat(pet.style.left) - before) === 60 ? '60px' : '不一致', '60px');

  window.dispatchEvent(ev('mouseup', ax, ay, 560, 500));
  ok('松手 -> landed（未被误判成单击）', S(), 'landed');

  // 纯单击（屏幕坐标完全不动）必须走互动分支，不能被当成拖拽
  window.App.force('idle');
  // 判定框默认 hidden，getBoundingClientRect 是 0，所以按 theme 的相对坐标算头心。
  // POPO_THEME 是 const 声明的全局词法绑定，不在 window 上，直接裸引用。
  const hb = POPO_THEME.hitBoxes.head;
  const pr2 = pet.getBoundingClientRect();
  const cx2 = pr2.left + (hb.x + hb.w / 2) * pr2.width;
  const cy2 = pr2.top + (hb.y + hb.h / 2) * pr2.height;
  pet.dispatchEvent(ev('mousedown', cx2, cy2, 900, 900));
  window.dispatchEvent(ev('mouseup', cx2, cy2, 900, 900));
  ok('纯单击头部 -> pet_head（未被当成拖拽）', S(), 'pet_head');

  report(out);
} catch (e) {
  report([], String(e));
}
"""


def main() -> int:
    if not os.path.exists(PREVIEW):
        print(f"缺少 {PREVIEW}，先跑 python3 code/build/build_web.py", file=sys.stderr)
        return 2
    if not os.path.exists(CHROME):
        print("找不到 Google Chrome，无法运行本测试", file=sys.stderr)
        return 2

    with open(PREVIEW, encoding="utf-8") as f:
        page = f.read()
    page = page.replace("</body>", f"<script>{DRIVER}</script>\n</body>")

    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tf:
        tf.write(page)
        tmp = tf.name

    try:
        proc = subprocess.run(
            [CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
             "--virtual-time-budget=5000", "--window-size=1280,820", "--dump-dom",
             f"file://{tmp}"],
            capture_output=True, text=True, timeout=120,
        )
        dom = proc.stdout
    finally:
        os.unlink(tmp)

    body = html.unescape(dom)
    results = re.findall(r"^(PASS|FAIL) (.*)$", body, re.MULTILINE)
    if not results:
        print("没有取到测试结果，页面可能没跑起来", file=sys.stderr)
        return 2

    failed = 0
    for verdict, line in results:
        print(f"{verdict} {line}")
        if verdict == "FAIL":
            failed += 1
    print(f"\n通过 {len(results) - failed} / 失败 {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
