"""PopoHere 素材处理流水线。

读取 只读的 `素材/` 目录，用 rembg(u2net) 去掉背景，
统一裁切后归一化到固定画布并对齐"地面基线"，输出到 `themes/popo/`。

同时生成 macOS 菜单栏用的单色模板图标 `assets/tray_icon.png`。

用法:
    python3 tools/cutout.py
"""

from __future__ import annotations

import os
import sys
import time

from PIL import Image
from rembg import new_session, remove

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "素材")
THEME_DIR = os.path.join(ROOT, "themes", "popo")
ASSETS_DIR = os.path.join(ROOT, "assets")

# 归一化画布：所有状态共用，底部对齐，避免切换状态时宠物跳动
CANVAS = 640
MARGIN = 18
MAX_WORK = 1600  # rembg 输入长边上限，兼顾速度与质量


def cutout(img: Image.Image, session) -> Image.Image:
    """去背景，返回 RGBA 透明图。"""
    work = img.copy()
    work.thumbnail((MAX_WORK, MAX_WORK), Image.LANCZOS)
    out = remove(
        work,
        session=session,
        alpha_matting=True,
        alpha_matting_foreground_threshold=240,
        alpha_matting_background_threshold=10,
        alpha_matting_erode_size=6,
    )
    return out


def trim_and_normalize(out: Image.Image) -> Image.Image:
    """裁到内容 bbox，再等比缩放贴到统一画布，底部对齐。"""
    bbox = out.split()[3].getbbox()
    if not bbox:
        return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    pad = 4
    bbox = (
        max(0, bbox[0] - pad),
        max(0, bbox[1] - pad),
        min(out.width, bbox[2] + pad),
        min(out.height, bbox[3] + pad),
    )
    content = out.crop(bbox)

    box_w = CANVAS - 2 * MARGIN
    box_h = CANVAS - 2 * MARGIN
    scale = min(box_w / content.width, box_h / content.height)
    new_w = max(1, round(content.width * scale))
    new_h = max(1, round(content.height * scale))
    content = content.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    x = (CANVAS - new_w) // 2
    y = (CANVAS - MARGIN) - new_h  # 底部对齐 = 地面基线
    canvas.paste(content, (x, y), content)
    return canvas


def make_tray_icon(source: Image.Image) -> Image.Image:
    """从一张抠好的图生成 macOS 菜单栏模板图标（纯黑 + alpha）。"""
    size = 44  # 22pt @2x
    im = source.copy()
    im.thumbnail((size, size), Image.LANCZOS)
    alpha = im.split()[3]
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    black = Image.new("RGBA", im.size, (0, 0, 0, 255))
    icon.paste(black, ((size - im.width) // 2, (size - im.height) // 2), alpha)
    return icon


def main() -> int:
    if not os.path.isdir(SRC):
        print(f"找不到素材目录: {SRC}", file=sys.stderr)
        return 1

    os.makedirs(THEME_DIR, exist_ok=True)
    os.makedirs(ASSETS_DIR, exist_ok=True)

    files = sorted(
        f for f in os.listdir(SRC) if f.lower().endswith(".png") and not f.startswith(".")
    )
    if not files:
        print("素材目录里没有 PNG", file=sys.stderr)
        return 1

    print(f"加载 u2net 模型…", flush=True)
    session = new_session("u2net")

    results = {}
    for name in files:
        state = os.path.splitext(name)[0]
        t0 = time.time()
        img = Image.open(os.path.join(SRC, name)).convert("RGBA")
        out = cutout(img, session)
        norm = trim_and_normalize(out)
        dst = os.path.join(THEME_DIR, f"{state}.png")
        norm.save(dst)
        results[state] = norm
        print(f"OK  {state:<10} {img.size} -> {norm.size}  ({time.time() - t0:.1f}s)", flush=True)

    tray_src = results.get("menu") or next(iter(results.values()))
    tray = make_tray_icon(tray_src)
    tray.save(os.path.join(ASSETS_DIR, "tray_icon.png"))
    print(f"OK  tray_icon  {tray.size}")

    # QA 用的总览图：棋盘格背景，方便检查白边 / 残留
    cols = 4
    tw = 200
    rows = (len(results) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * tw), (235, 235, 235))
    for i, (state, im) in enumerate(sorted(results.items())):
        tile = Image.new("RGB", (tw, tw))
        tile.paste(Image.new("RGB", (tw // 2, tw // 2), (200, 200, 200)), (0, 0))
        tile.paste(Image.new("RGB", (tw // 2, tw // 2), (200, 200, 200)), (tw // 2, tw // 2))
        thumb = im.copy()
        thumb.thumbnail((tw - 8, tw - 8), Image.LANCZOS)
        tile.paste(thumb, ((tw - thumb.width) // 2, (tw - thumb.height) // 2), thumb)
        sheet.paste(tile, ((i % cols) * tw, (i // cols) * tw))
    qa_path = os.path.join("/tmp", "popo_qa_sheet.png")
    sheet.save(qa_path)
    print(f"QA 总览图: {qa_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
