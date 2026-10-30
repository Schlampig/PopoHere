"""生成 macOS 应用图标 AppIcon.icns。

用法：
    python3 code/build/make_icon.py                          # 默认用 pet_images/landed.png
    python3 code/build/make_icon.py code/pet_images/menu.png  # 也可以指定别的姿势

选图原则：主体水平居中、正脸清晰、姿态不要太扁。landed.png 的水平留白左右几乎相等
（x=[117,522] / 画布 640），是现成素材里最适合做图标的一张。

流程：裁到内容外框 → 等比缩放居中贴到正方形画布（留 14% 边距）→ 生成全套 iconset →
调用 iconutil 合成 .icns。
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

CODE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # code/
DEFAULT_SRC = os.path.join(CODE, "pet_images", "logo_1.png")
OUT = os.path.join(CODE, "pet_others", "AppIcon.icns")

# iconset 需要的尺寸：(输出名, 像素边长)
# 最大只到 256：本来 app 只有 640KB，图标如果做到 512/1024 会膨胀到 440KB/1MB，
# 明显不划算。而这是个 LSUIElement 应用、不进 Dock，图标基本只在 Finder 里露面，
# 256 完全够看。想要更高可自己在下面补 512 两档。
ICON_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
]

MARGIN = 0.14   # 内容四周留白比例，避免图标边缘顶到边框


def squared_im(src: str, size: int) -> Image.Image:
    """把透明 PNG 裁到内容外框，再等比居中放到 size×size 画布上。"""
    im = Image.open(src).convert("RGBA")
    bbox = im.split()[3].getbbox()
    if bbox:
        im = im.crop(bbox)
    w, h = im.size
    inner = int(size * (1 - MARGIN * 2))
    scale = min(inner / w, inner / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    im = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, ((size - nw) // 2, (size - nh) // 2), im)
    return canvas


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    if not os.path.exists(src):
        print(f"找不到素材 {src}", file=sys.stderr)
        return 1
    if shutil.which("iconutil") is None:
        print("找不到 iconutil，只能在 macOS 上运行", file=sys.stderr)
        return 1

    tmp = tempfile.mkdtemp(prefix="popoicon-")
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.makedirs(iconset)
    try:
        for name, px in ICON_SIZES:
            squared_im(src, px).save(os.path.join(iconset, name))
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT], check=True)
        print(f"生成 {OUT}  ({os.path.getsize(OUT) / 1024:.0f} KB)  来源={os.path.basename(src)}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
