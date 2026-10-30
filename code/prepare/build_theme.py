"""扫描素材目录，生成 `theme.json`。

用户只按 `<状态>_<序号>.png` 丢图，**不需要手写 JSON**——这个脚本把文件名翻译成契约。

    python3 code/prepare/build_theme.py
    python3 code/prepare/build_theme.py --check    # 只报告，不写文件

规则：
  - 同状态多张图 → 运行时等概率随机抽一张并锁定
  - 文件名不符规范（不在 STATE_DEFAULTS 里）→ 跳过并提示
  - 已存在的 `behavior` 段会被保留，方便手调参数不被覆盖
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

CODE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # code/
IMG = os.path.join(CODE, "pet_images")
THEME = os.path.join(IMG, "theme.json")
THEME_VERSION = "2.0"

# 每个状态的默认表现。duration 为 None 表示"一直持续，等事件打断"
STATE_DEFAULTS = {
    "idle":     {"loop": True,  "motion": "breathe",      "duration": None},
    "touch":    {"loop": False, "motion": "none",         "duration": 1.5,
                 "bubbles": ["❤️", "😌", "✨"]},
    "scratch":  {"loop": False, "motion": "shake",        "duration": 1.5, "bubble": "💢"},
    "play":     {"loop": False, "motion": "bob-walk",     "duration": 2.5},
    "sleep":    {"loop": True,  "motion": "breathe-slow", "duration": None, "bubble": "💤"},
    "dragging": {"loop": True,  "motion": "none",         "duration": None},
    "menu":     {"loop": True,  "motion": "none",         "duration": None},
    "startled": {"loop": False, "motion": "shake",        "duration": 1.0, "bubble": "❗"},
    "landed":   {"loop": False, "motion": "drop",         "duration": 0.8},
}

BEHAVIOR_DEFAULTS = {
    "idle_duration_sec": 5,
    "idle_to_play_probability": 0.35,
    "touch_repeat_window_sec": 4,
    "touch_scratch_threshold": 10,
    "scratch_cooldown_sec": 6,
    "click_max_drift_px": 5,
    "click_max_duration_ms": 300,
    "menu_timeout_sec": 8,
}

# 单一命中区：整只猫都是"撸它"
HIT_BOXES = {"body": {"x": 0.04, "y": 0.04, "w": 0.92, "h": 0.92}}

# 非状态素材，不参与 states
NON_STATE = {"logo", "menubar"}

PATTERN = re.compile(r"^(?P<state>[a-z]+)(?:_(?P<idx>\d+))?\.png$")


def scan() -> tuple[dict[str, list[tuple[int, str]]], list[str]]:
    found: dict[str, list[tuple[int, str]]] = {}
    unknown: list[str] = []
    for name in sorted(os.listdir(IMG)):
        if not name.lower().endswith(".png"):
            continue
        m = PATTERN.match(name)
        if not m:
            unknown.append(name)
            continue
        state = m.group("state")
        if state in NON_STATE:
            continue
        if state not in STATE_DEFAULTS:
            unknown.append(name)
            continue
        idx = int(m.group("idx") or 1)
        found.setdefault(state, []).append((idx, name))
    return found, unknown


def build() -> dict:
    found, unknown = scan()

    # 只有同版本重跑时才保留手调过的 behavior；跨版本升级一律用新默认值，
    # 否则 v1.0 的旧参数（如 menu_timeout_sec=2）会被带进 v2.0。
    behavior = dict(BEHAVIOR_DEFAULTS)
    if os.path.exists(THEME):
        try:
            with open(THEME, encoding="utf-8") as f:
                old = json.load(f)
            if old.get("version") == THEME_VERSION:
                for k, v in old.get("behavior", {}).items():
                    if k in BEHAVIOR_DEFAULTS:
                        behavior[k] = v
        except (json.JSONDecodeError, OSError):
            pass

    states = {}
    for state, defaults in STATE_DEFAULTS.items():
        files = found.get(state)
        if not files:
            continue
        visuals = [name for _, name in sorted(files)]
        states[state] = {"visuals": visuals, **defaults}

    theme = {
        "id": "popo",
        "displayName": "Popo",
        "version": THEME_VERSION,
        "behavior": behavior,
        "states": states,
        "hitBoxes": HIT_BOXES,
    }

    missing = [s for s in STATE_DEFAULTS if s not in states]
    if missing:
        print(f"⚠️  缺少状态素材：{', '.join(missing)}（游戏仍可跑，但这些状态不会出现）",
              file=sys.stderr)
    if unknown:
        print(f"⚠️  以下文件名不合规范，已跳过：{', '.join(unknown)}", file=sys.stderr)
    return theme


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只报告，不写文件")
    args = ap.parse_args()

    if not os.path.isdir(IMG):
        print(f"找不到素材目录 {IMG}", file=sys.stderr)
        return 1

    theme = build()
    for state, spec in theme["states"].items():
        print(f"  {state:<10} {len(spec['visuals'])} 张  {spec['visuals'][:3]}{'…' if len(spec['visuals']) > 3 else ''}")

    if args.check:
        return 0

    with open(THEME, "w", encoding="utf-8") as f:
        json.dump(theme, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"\n写入 {THEME}（{len(theme['states'])} 个状态）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
