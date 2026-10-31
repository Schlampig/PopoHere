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
import os
import re
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
PATTERN = re.compile(r"^(?P<state>[a-z]+)(?:_(?P<idx>\d+))?$")

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


def make_tray_icon(source: Image.Image, size: int = 44) -> Image.Image:
    """从一张抠好的图生成 macOS 菜单栏模板图标（纯黑 + alpha）。

    关键：**先裁到内容再缩放**。之前直接在 640 画布上 thumbnail，
    猫只占中间一小块，到菜单栏里就成了一个 8px 的小点。
    """
    im = source.copy()
    bbox = im.split()[3].getbbox()
    if bbox:
        im = im.crop(bbox)

    pad = 2                                  # 22pt 图标留一点呼吸
    inner = size - pad * 2
    im.thumbnail((inner, inner), Image.LANCZOS)

    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    black = Image.new("RGBA", im.size, (0, 0, 0, 255))
    icon.paste(black, ((size - im.width) // 2, (size - im.height) // 2), im.split()[3])
    return icon


def harmonize(results: dict) -> None:
    """同一状态里多张图，按"视觉面积"统一大小（只缩不放）。

    逐张 fit-to-box 会让"躺着的猫"和"坐着的猫"占差不多的宽/高，切状态或重新抽帧时
    看着像忽大忽小。用 alpha 面积当"体量"代理，把偏大的那几张缩到同状态的中位数。
    只缩不放：放大一定会撞到画布边界、反而被裁。
    """
    groups: dict[str, list[str]] = {}
    for stem in results:
        m = PATTERN.match(stem)
        if m:
            groups.setdefault(m.group("state"), []).append(stem)

    for state, stems in groups.items():
        if len(stems) < 2:
            continue
        sizes = []
        for stem in stems:
            alpha = results[stem].split()[3]
            sizes.append((stem, (sum(alpha.getdata()) / 255.0) ** 0.5))
        # 取偏小的那个中位数：只缩不放，所以基准要往下靠，否则大图永远缩不下来
        target = sorted(v for _, v in sizes)[(len(sizes) - 1) // 2]
        for stem, value in sizes:
            factor = target / value if value > 0 else 1.0
            if factor >= 0.98:                    # 本来就小，不放大
                continue
            im = results[stem]
            w, h = im.size
            nw, nh = max(1, round(w * factor)), max(1, round(h * factor))
            small = im.resize((nw, nh), Image.LANCZOS)
            canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            canvas.paste(small, ((w - nw) // 2, h - nh), small)     # 底边对齐
            results[stem] = canvas
            canvas.save(os.path.join(OUT_DIR, f"{stem}.png"))
            print(f"    归一 {stem:<14} ×{factor:.2f}")


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


def check() -> int:
    """校验命名：每张原图都要能对上状态表。

    刻意**不读 theme.json**——那份文件是上一次运行的产物，换素材时它还是旧名字，
    拿它校验新素材只会制造假报错。真正该守的规范是 build_theme.STATE_DEFAULTS。
    """
    from build_theme import STATE_DEFAULTS, NON_STATE

    names = list_sources()
    have = {os.path.splitext(f)[0] for f in names}
    unknown, counter = [], {}

    for stem in sorted(have):
        m = PATTERN.match(stem)
        if not m:
            unknown.append(stem)
            continue
        state = m.group("state")
        if state in NON_STATE:
            continue
        if state not in STATE_DEFAULTS:
            unknown.append(stem)
            continue
        counter.setdefault(state, []).append(int(m.group("idx") or 1))

    for state, idxs in sorted(counter.items()):
        dup = {i for i in idxs if idxs.count(i) > 1}
        if dup:
            unknown.append(f"{state} 序号重复 {sorted(dup)}")

    missing = [s for s in STATE_DEFAULTS
               if s != "menu" and s not in counter]      # menu 可以复用别的姿势

    print(f"共 {len(names)} 张原图，覆盖 {len(counter)} 个状态：")
    for state in sorted(counter):
        print(f"  {state:<10} {len(counter[state])} 张")

    if missing:
        print(f"\n⚠️  这些状态没有素材（运行时会被跳过）：{', '.join(missing)}")
    if unknown:
        print("\n❌ 以下文件不符合命名规范（应形如 touch_1.png）：")
        for u in unknown:
            print("  -", u)
        return 1
    if missing:
        return 0
    print("\n命名校验通过")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只校验，不处理图片")
    args = ap.parse_args()

    if args.check:
        return check()

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

    harmonize(results)

    # 清掉上一版遗留的贴图：新素材可能比旧的少几张，留着会被 build_theme 扫进去
    produced = set(results)
    stale = [f for f in os.listdir(OUT_DIR)
             if f.lower().endswith(".png") and os.path.splitext(f)[0] not in produced]
    for f in sorted(stale):
        os.remove(os.path.join(OUT_DIR, f))
    if stale:
        print(f"清理旧贴图 {len(stale)} 张：{', '.join(sorted(stale))}")

    # 菜单栏图标：优先 menubar，其次 menu，最后随便一张
    tray_src = results.get("menubar") or results.get("menu") or next(iter(results.values()))
    make_tray_icon(tray_src).save(os.path.join(OTHER_DIR, "tray_icon.png"))
    print("OK  tray_icon.png（菜单栏模板图标）")

    save_qa_sheet(results, OUT_QA)
    print(f"QA 总览图: {OUT_QA}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
