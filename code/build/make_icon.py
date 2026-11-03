"""生成 macOS 应用图标 AppIcon.icns。

用法：
    python3 code/build/make_icon.py                          # 默认用 pet_images/logo_1.png
    python3 code/build/make_icon.py code/pet_images/menu.png  # 也可以指定别的姿势
    python3 code/build/make_icon.py --plain                   # 不要白色卡片底

logo_1.png 是线稿，直接透明底放到 32px 会糊成一团灰，所以默认垫一张暖白圆角卡片，
小尺寸下靠"深色线条 + 白底"的对比才认得出是猫。

选图原则：主体水平居中、正脸清晰、轮廓不要过于扁平。默认使用 logo_1.png
（线稿），若换成照片类素材，建议选择正脸且四周留白均衡的一张。

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

MARGIN = 0.14      # 透明底时内容四周留白
CARD_INSET = 0.06  # 卡片离画布边缘
CARD_RADIUS = 0.24 # 圆角半径（相对卡片边长，接近 macOS Big Sur 的比例）
CARD_PAD = 0.11    # 卡片内再留一圈，避免线稿顶边
CARD_BG = (251, 248, 242, 255)


def _place(im: Image.Image, size: int, inner: int) -> Image.Image:
    """把 im 等比缩到 inner 内，居中贴到 size 画布上。"""
    w, h = im.size
    scale = min(inner / w, inner / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    im = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, ((size - nw) // 2, (size - nh) // 2), im)
    return canvas


def squared_im(src: str, size: int, card: bool = True) -> Image.Image:
    """裁到内容外框 → 居中放到 size×size 画布（可垫圆角卡片）。"""
    im = Image.open(src).convert("RGBA")
    bbox = im.split()[3].getbbox()
    if bbox:
        im = im.crop(bbox)

    if not card:
        return _place(im, size, int(size * (1 - MARGIN * 2)))

    inset = max(1, round(size * CARD_INSET))
    card_size = size - inset * 2
    radius = max(2, round(card_size * CARD_RADIUS))
    # 4× 超采样再缩回来，避免小尺寸圆角出现锯齿
    ss = 4
    bg = Image.new("RGBA", (card_size * ss, card_size * ss), (0, 0, 0, 0))
    from PIL import ImageDraw
    ImageDraw.Draw(bg).rounded_rectangle(
        (0, 0, card_size * ss - 1, card_size * ss - 1),
        radius=radius * ss, fill=CARD_BG)
    bg = bg.resize((card_size, card_size), Image.LANCZOS)

    pad = round(card_size * CARD_PAD)
    art = _place(im, card_size, card_size - pad * 2)
    bg.alpha_composite(art)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(bg, (inset, inset))
    return canvas


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    card = "--plain" not in sys.argv
    src = args[0] if args else DEFAULT_SRC
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
            squared_im(src, px, card=card).save(os.path.join(iconset, name))
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT], check=True)
        print(f"生成 {OUT}  ({os.path.getsize(OUT) / 1024:.0f} KB)  来源={os.path.basename(src)}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
