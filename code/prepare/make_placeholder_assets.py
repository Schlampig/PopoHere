"""研发期占位素材：把现有几张图铺成 v2.0 需要的完整命名体系。

**这是临时脚本**，只为在正式素材到位前把整条流水线跑通、验证框架。
用户按 PRD 拍好真图后，直接用 `cutout.py` 覆盖 `code/pet_images/`，然后删掉本脚本即可。

做的事：
  1. 从现有素材复制出 `<state>_<n>.png` 全套（重复填充，张数符合 PRD 清单）
  2. 生成 `logo_1.png`（512，应用图标/面板 logo）与 `menubar_1.png`（88，菜单栏剪影）
  3. 清理 v1.0 遗留的裸名字文件（idle.png / pet_head.png / walk.png …）

用法：
    python3 code/prepare/make_placeholder_assets.py
"""

from __future__ import annotations

import os
import shutil

from PIL import Image

CODE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # code/
IMG = os.path.join(CODE, "pet_images")

# 目标名 → 源文件（源文件都来自 v1.0 的产物）
PLAN = {
    "idle":     ["idle.png"] * 4,
    "touch":    ["pet_head.png", "pet_paw.png", "pet_head.png", "pet_paw.png", "pet_head.png", "pet_paw.png"],
    "scratch":  ["scratch.png"] * 3,
    "play":     ["walk.png", "landed.png", "walk.png", "landed.png", "walk.png", "landed.png"],
    "sleep":    ["sleep.png"] * 4,
    "dragging": ["dragging.png"] * 2,
    "menu":     ["menu.png"] * 2,
    "startled": ["startled.png"] * 2,
    "landed":   ["landed.png"] * 2,
}

V1_LEFTOVERS = ["idle.png", "pet_head.png", "pet_paw.png", "walk.png",
                "scratch.png", "sleep.png", "startled.png", "dragging.png",
                "menu.png", "landed.png"]


def load(name: str) -> Image.Image:
    path = os.path.join(IMG, name)
    if not os.path.exists(path):
        raise SystemExit(f"缺少源素材 {path}")
    return Image.open(path).convert("RGBA")


def main() -> int:
    # 先把要用的源图读进内存，避免边写边删把源文件弄没
    sources = {name: load(name) for name in {s for v in PLAN.values() for s in v}}

    for state, files in PLAN.items():
        for i, src in enumerate(files, start=1):
            dst = os.path.join(IMG, f"{state}_{i}.png")
            shutil.copyfile(os.path.join(IMG, src), dst)
            print(f"  {src:<14} -> {state}_{i}.png")

    # logo：512 见方，主体占 72%
    base = sources["landed.png"]
    for name, size, margin in [("logo_1.png", 512, 0.14)]:
        im = base.copy()
        bbox = im.split()[3].getbbox()
        if bbox:
            im = im.crop(bbox)
        inner = int(size * (1 - margin * 2))
        scale = min(inner / im.width, inner / im.height)
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2), im)
        canvas.save(os.path.join(IMG, name))
        print(f"  logo_1.png ({size}px)")

    # 菜单栏剪影：纯黑 + alpha，88 见方
    im = sources["menu.png"]
    bbox = im.split()[3].getbbox()
    if bbox:
        im = im.crop(bbox)
    size = 88
    scale = min(size / im.width, size / im.height)
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
    alpha = im.split()[3]
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(Image.new("RGBA", im.size, (0, 0, 0, 255)),
               ((size - im.width) // 2, (size - im.height) // 2), alpha)
    icon.save(os.path.join(IMG, "menubar_1.png"))
    print("  menubar_1.png (88px)")

    # 清掉 v1.0 的裸名字
    for name in V1_LEFTOVERS:
        path = os.path.join(IMG, name)
        if os.path.exists(path):
            os.remove(path)
            print(f"  删除旧命名 {name}")

    print("\n占位素材就绪。下一步：python3 code/prepare/build_theme.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
