"""把 src 里的模板 / JS / 主题 + 抠图素材 打包成单个自包含 HTML。

    python3 tools/build_prototype.py              # 预览原型 → prototype/index.html
    python3 tools/build_prototype.py --native     # 原生外壳用 → build/app/index.html

两种产物唯一的区别是 __NATIVE__ 标志：原生模式下隐藏调试面板与假桌面背景，
并通过 window.App 暴露给 Objective-C 外壳调用。
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "prototype", "src")
THEME_DIR = os.path.join(ROOT, "themes", "popo")
PREVIEW_OUT = os.path.join(ROOT, "prototype", "index.html")
NATIVE_OUT = os.path.join(ROOT, "build", "app", "index.html")

EMBED_SIZE = 420  # 内嵌贴图边长，够清晰且体积小（webP ~30KB/张）


def read(name: str) -> str:
    with open(os.path.join(SRC_DIR, name), encoding="utf-8") as f:
        return f.read()


def image_data_uri(path: str) -> str:
    im = Image.open(path).convert("RGBA")
    im = im.resize((EMBED_SIZE, EMBED_SIZE), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "WEBP", quality=88, method=6)
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/webp;base64,{b64}"


def build(out_path: str, native: bool) -> int:
    with open(os.path.join(THEME_DIR, "theme.json"), encoding="utf-8") as f:
        theme = json.load(f)

    needed = []
    for spec in theme["states"].values():
        for v in spec.get("visuals", []):
            if v not in needed:
                needed.append(v)

    images = {}
    missing = []
    for name in needed:
        path = os.path.join(THEME_DIR, name)
        if not os.path.exists(path):
            missing.append(name)
            continue
        images[name] = image_data_uri(path)

    if missing:
        print(f"警告：缺少素材 {missing}", file=sys.stderr)

    html = read("template.html")
    html = html.replace("__IMAGES__", "const POPO_IMAGES = " + json.dumps(images) + ";")
    html = html.replace("__THEME__", "const POPO_THEME = " + json.dumps(theme, ensure_ascii=False) + ";")
    html = html.replace("__NATIVE__", "const POPO_NATIVE = " + ("true" if native else "false") + ";")
    html = html.replace("__APP_JS__", read("app.js"))

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"生成 {out_path}  ({os.path.getsize(out_path) / 1024:.0f} KB, {len(images)} 张素材, "
          f"{'原生' if native else '预览'}模式)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--native", action="store_true", help="生成给 .app 原生外壳用的版本")
    args = ap.parse_args()
    if args.native:
        return build(NATIVE_OUT, True)
    return build(PREVIEW_OUT, False)


if __name__ == "__main__":
    raise SystemExit(main())
