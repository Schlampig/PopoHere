"""把代码模块 + 主题 + 素材内联成一个自包含 HTML。

    python3 code/build/build_web.py              # 预览版 → code/build/out/preview.html
    python3 code/build/build_web.py --native     # 原生版 → code/build/out/native.html

两个产物的唯一区别是 __NATIVE__ 标志：原生模式下隐藏调试面板与假桌面背景，
并通过 window.App 暴露给 Objective-C 外壳调用。

模块拼装顺序 = 依赖顺序，别随便调：
    func_state → func_render → func_input → func_menu → main
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import sys

from PIL import Image

CODE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # code/
TEMPLATE = os.path.join(CODE, "prototype", "template.html")
ASSETS = os.path.join(CODE, "pet_images")
OUT_DIR = os.path.join(CODE, "build", "out")

CORE_MODULES = [
    os.path.join(CODE, "core", "func_state", "state_machine.js"),
    os.path.join(CODE, "core", "func_render", "renderer.js"),
    os.path.join(CODE, "core", "func_input", "input.js"),
    os.path.join(CODE, "core", "func_menu", "menu.js"),
    os.path.join(CODE, "core", "main.js"),
]

EMBED_SIZE = 420   # 内嵌贴图边长：够清晰，10 张加起来约 420KB


def image_data_uri(path: str) -> str:
    im = Image.open(path).convert("RGBA").resize((EMBED_SIZE, EMBED_SIZE), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=88, method=6)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def build(out_path: str, native: bool) -> int:
    theme = json.loads(read(os.path.join(ASSETS, "theme.json")))

    needed = []
    for spec in theme["states"].values():
        for v in spec.get("visuals", []):
            if v not in needed:
                needed.append(v)

    # 同一张图可能被多个状态复用（尤其占位素材）。按内容去重成"唯一图池"，
    # 再给每个文件名一个索引——直接往 JSON 里塞多份 base64 会让体积翻好几倍。
    blobs: list[str] = []
    index: dict[str, int] = {}
    images: dict[str, int] = {}
    missing = []
    for name in needed:
        path = os.path.join(ASSETS, name)
        if not os.path.exists(path):
            missing.append(name)
            continue
        digest = hashlib.md5(open(path, "rb").read()).hexdigest()
        if digest not in index:
            index[digest] = len(blobs)
            blobs.append(image_data_uri(path))
        images[name] = index[digest]
    if missing:
        print(f"警告：缺少素材 {missing}", file=sys.stderr)

    images_js = (
        "const POPO_BLOBS = " + json.dumps(blobs) + ";\n"
        "const POPO_IMAGES = (() => { const m = " + json.dumps(images) +
        "; const o = {}; for (const k in m) o[k] = POPO_BLOBS[m[k]]; return o; })();"
    )

    core_js = "\n\n".join(
        f"/* ==== {os.path.relpath(m, CODE)} ==== */\n" + read(m) for m in CORE_MODULES
    )

    html = read(TEMPLATE)
    html = html.replace("__IMAGES__", images_js)
    html = html.replace("__THEME__", "const POPO_THEME = " + json.dumps(theme, ensure_ascii=False) + ";")
    html = html.replace("__NATIVE__", "const POPO_NATIVE = " + ("true" if native else "false") + ";")
    html = html.replace("__CORE_JS__", core_js)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"生成 {out_path}  ({os.path.getsize(out_path) / 1024:.0f} KB, "
          f"{len(images)} 个引用 / {len(blobs)} 张不同图, "
          f"{'原生' if native else '预览'}模式)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--native", action="store_true", help="生成给 .app 用的版本")
    args = ap.parse_args()
    name = "native.html" if args.native else "preview.html"
    return build(os.path.join(OUT_DIR, name), args.native)


if __name__ == "__main__":
    raise SystemExit(main())
