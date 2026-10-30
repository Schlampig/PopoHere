#!/usr/bin/env python3
"""连点（猛点）回归测试

    python3 code/build/build_web.py && python3 code/test/click_mash_test.py

背景：用户"拼命点击"时桌宠不进入挠人状态。根因有三层，这个测试逐层锁住：

  1. 位移阈值 5px 太紧——连点时手抖 6~10px 就被判成拖拽，每一轮都变成
     dragging → landed → idle，连撸计数永远是 0。
  2. `startled` / `landed` 两个过渡态吞掉了点击，一轮猛点被动画吃掉大半。
  3. 达到阈值后还要等 touch 播完（1.5s）才翻脸，用户越点越看不到结果。

本测试跑的是**真实产物**（build/out/preview.html）里的 input + state 两层，
不是纯逻辑单测，所以能覆盖"指针漂移多少才算拖拽"这种和 DOM 事件贴得很近的规则。
"""
import os
import re
import subprocess
import sys
import tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CODE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW = os.path.join(CODE, "build", "out", "preview.html")

DRIVER = r"""
<script>
(async () => {
  const out = [];
  const ok = (label, got, want) => out.push((got === want ? 'PASS' : 'FAIL') +
      ' ' + label + ' | got=' + got + ' want=' + want);
  const S = () => window.App.state();
  const K = () => window.App.streak();
  const pet = document.getElementById('pet');

  const ev = (type, sx, sy) => new MouseEvent(type, {
    bubbles: true, cancelable: true, button: 0,
    clientX: 100, clientY: 100, screenX: sx, screenY: sy });

  // 一次"带手抖的单击"：按下 → 指针漂移 drift 像素 → 松开
  function tap(drift, sx) {
    pet.dispatchEvent(ev('mousedown', sx, 500));
    if (drift) window.dispatchEvent(ev('mousemove', sx + drift, 500));
    window.dispatchEvent(ev('mouseup', sx + drift, 500));
  }

  const scene = (location.hash || '').replace('#', '') || 'mash';

  if (scene === 'mash') {
    // 关键场景：每次单击都带 8px 手抖（旧阈值 5px 会把每一下都判成拖拽）
    for (let i = 0; i < 9; i++) tap(8, 100 + i * 8);
    ok('猛点 9 下：停在 touch', S(), 'touch');
    ok('猛点 9 下：计数为 9', K(), 9);
    tap(8, 100 + 9 * 8);
    ok('第 10 下当场翻脸（不用等动画）', S(), 'scratch');
    ok('计数到 10', K(), 10);
  }

  if (scene === 'drag') {
    // 阈值仍然有效：20px 必须被认成拖拽，不能被"宽容"吞掉
    pet.dispatchEvent(ev('mousedown', 100, 500));
    window.dispatchEvent(ev('mousemove', 120, 500));
    ok('20px 位移进入 dragging', S(), 'dragging');
    window.dispatchEvent(ev('mouseup', 120, 500));
    ok('松手 → landed', S(), 'landed');
  }

  if (scene === 'startled') {
    window.App.force('startled');
    tap(0, 300);
    ok('惊醒中点击 → 直接进入 touch', S(), 'touch');
    ok('开始计数', K(), 1);
  }

  if (scene === 'landed') {
    window.App.force('landed');
    tap(0, 300);
    ok('落地中点击 → 进入 touch', S(), 'touch');
  }

  const pre = document.createElement('pre');
  pre.textContent = out.join('\n');
  document.body.appendChild(pre);
})();
</script>
"""


def run_scene(page: str, scene: str) -> list[str]:
    out = subprocess.run(
        [CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
         f"--user-data-dir=/tmp/popo/mash-{scene}",
         "--virtual-time-budget=4000", "--window-size=1280,820",
         "--dump-dom", f"file://{page}#{scene}"],
        capture_output=True, text=True,
    ).stdout
    body = out.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
    # <pre> 里的第一行会紧跟在标签后面、最后一行带着 </pre>，先把标签换成换行再筛
    text = re.sub(r"<[^>]*>", "\n", body)
    return [ln.strip() for ln in text.splitlines()
            if ln.strip().startswith(("PASS ", "FAIL "))]


def main() -> int:
    if not os.path.exists(PREVIEW):
        print(f"缺少 {PREVIEW}，先跑 python3 code/build/build_web.py", file=sys.stderr)
        return 2

    html = open(PREVIEW, encoding="utf-8").read().replace("</body>", DRIVER + "</body>")
    tmp = tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8")
    tmp.write(html)
    tmp.close()

    total = failed = 0
    try:
        for scene in ("mash", "drag", "startled", "landed"):
            lines = run_scene(tmp.name, scene)
            if not lines:
                print(f"FAIL {scene}: 没拿到断言输出")
                failed += 1
                continue
            for ln in lines:
                print(ln)
                total += 1
                if ln.startswith("FAIL"):
                    failed += 1
    finally:
        os.unlink(tmp.name)

    print(f"\n通过 {total - failed} / 失败 {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
