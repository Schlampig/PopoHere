"""PopoHere · 素材预处理：原始照片 → 干净的透明贴图。

流水线的第一步，也是唯一一步会碰用户原始素材的地方：

    source/origin_images/*.png   (用户自己丢进来的照片，任意尺寸/背景)
              │  rembg(u2net) 去背景
              │  裁到内容外框 → 等比缩放 → 统一画布、底部对齐
              ▼
    code/pet_images/*.png        (桌宠真正用的贴图)
    code/pet_others/tray_icon.png

命名约定（与 theme.json 里的 visuals 一一对应）：
    <state>.png            该状态只有一张
    <state>_<序号>.png     该状态有多张，序号从 1 开始，运行时等概率随机抽

用法：
    python3 code/prepare/cutout.py
    python3 code/prepare/cutout.py --check      # 只校验命名，不处理
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time

from PIL import Image

try:
    from rembg import new_session, remove
except ImportError:          # --check 只用来看命名，不需要装模型
    new_session = remove = None

CODE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # code/
ROOT = os.path.dirname(CODE)                                          # 仓库根
SRC = os.path.join(ROOT, "source", "origin_images")
OUT_DIR = os.path.join(CODE, "pet_images")
OTHER_DIR = os.path.join(CODE, "pet_others")
OUT_QA = os.path.join(CODE, "build", "out", "qa_sheet.png")

# 归一化画布：所有状态共用，底部对齐，避免切换状态时宠物跳动
CANVAS = 640
MARGIN = 18
MAX_WORK = 1600   # rembg 输入长边上限，兼顾速度与质量


def cutout(img: Image.Image, session) -> Image.Image:
    """去背景，返回 RGBA 透明图。"""
    work = img.copy()
    work.thumbnail((MAX_WORK, MAX_WORK), Image.LANCZOS)
    return remove(
        work,
        session=session,
        alpha_matting=True,
        alpha_matting_foreground_threshold=240,
        alpha_matting_background_threshold=10,
        alpha_matting_erode_size=6,
    )


def trim_and_normalize(out: Image.Image) -> Image.Image:
    """裁到内容 bbox，再等比缩放贴到统一画布，底部对齐（= 地面基线）。"""
    bbox = out.split()[3].getbbox()
    if not bbox:
        return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    pad = 4
    bbox = (
        max(0, bbox[0] - pad), max(0, bbox[1] - pad),
        min(out.width, bbox[2] + pad), min(out.height, bbox[3] + pad),
    )
    content = out.crop(bbox)

    box = CANVAS - 2 * MARGIN
    scale = min(box / content.width, box / content.height)
    new_w = max(1, round(content.width * scale))
    new_h = max(1, round(content.height * scale))
    content = content.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(content, ((CANVAS - new_w) // 2, (CANVAS - MARGIN) - new_h), content)
    return canvas


def make_tray_icon(source: Image.Image) -> Image.Image:
    """从一张抠好的图生成 macOS 菜单栏模板图标（纯黑 + alpha）。"""
    size = 44   # 22pt @2x
    im = source.copy()
    im.thumbnail((size, size), Image.LANCZOS)
    alpha = im.split()[3]
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    black = Image.new("RGBA", im.size, (0, 0, 0, 255))
    icon.paste(black, ((size - im.width) // 2, (size - im.height) // 2), alpha)
    return icon


def save_qa_sheet(results: dict, path: str) -> None:
    """棋盘格总览图，方便肉眼检查白边 / 残留背景。"""
    cols, tw = 4, 200
    rows = (len(results) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * tw), (235, 235, 235))
    for i, (_, im) in enumerate(sorted(results.items())):
        tile = Image.new("RGB", (tw, tw), (245, 245, 245))
        tile.paste(Image.new("RGB", (tw // 2, tw // 2), (210, 210, 210)), (0, 0))
        tile.paste(Image.new("RGB", (tw // 2, tw // 2), (210, 210, 210)), (tw // 2, tw // 2))
        thumb = im.copy()
        thumb.thumbnail((tw - 8, tw - 8), Image.LANCZOS)
        tile.paste(thumb, ((tw - thumb.width) // 2, (tw - thumb.height) // 2), thumb)
        sheet.paste(tile, ((i % cols) * tw, (i // cols) * tw))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)


def list_sources() -> list[str]:
    return sorted(
        f for f in os.listdir(SRC) if f.lower().endswith(".png") and not f.startswith(".")
    )


def check(theme_path: str) -> int:
    """校验：theme.json 里要的图，source 里是否都有对应原图。"""
    with open(theme_path, encoding="utf-8") as f:
        theme = json.load(f)
    have = {os.path.splitext(f)[0] for f in list_sources()}
    missing = []
    for state, spec in theme["states"].items():
        for visual in spec.get("visuals", []):
            stem = os.path.splitext(visual)[0]
            if stem not in have:
                missing.append(f"{state} → {visual}")
    if missing:
        print("以下素材在 source/origin_images 里找不到：")
        for m in missing:
            print("  -", m)
        return 1
    print(f"命名校验通过：{len(have)} 张原图覆盖了 theme.json 的全部状态")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只校验，不处理图片")
    args = ap.parse_args()

    theme_path = os.path.join(OUT_DIR, "theme.json")
    if args.check:
        return check(theme_path)

    if not os.path.isdir(SRC):
        print(f"找不到原始素材目录: {SRC}", file=sys.stderr)
        return 1
    files = list_sources()
    if not files:
        print("source/origin_images 里没有 PNG", file=sys.stderr)
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(OTHER_DIR, exist_ok=True)

    print("加载 u2net 模型…", flush=True)
    session = new_session("u2net")

    results = {}
    for name in files:
        stem = os.path.splitext(name)[0]
        t0 = time.time()
        img = Image.open(os.path.join(SRC, name)).convert("RGBA")
        norm = trim_and_normalize(cutout(img, session))
        norm.save(os.path.join(OUT_DIR, f"{stem}.png"))
        results[stem] = norm
        print(f"OK  {stem:<16} {img.size} -> {norm.size}  ({time.time() - t0:.1f}s)", flush=True)

    # 菜单栏图标优先用 menu 那张，没有就随便挑一张
    tray_src = results.get("menu") or next(iter(results.values()))
    make_tray_icon(tray_src).save(os.path.join(OTHER_DIR, "tray_icon.png"))
    print("OK  tray_icon.png")

    save_qa_sheet(results, OUT_QA)
    print(f"QA 总览图: {OUT_QA}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
