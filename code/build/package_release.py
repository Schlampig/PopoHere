"""打包发布包：把 dist/PopoHere.app 连同启动脚本和说明压成一个 zip。

    python3 code/build/package_release.py              # → code/build/releases/PopoHere-<版本>.zip
    python3 code/build/package_release.py --version 1.1.0

包内结构（顶层是一个文件夹，避免解压后文件散落一地）：

    PopoHere-v0.1.0/
    ├── PopoHere.app
    ├── 启动 PopoHere.command      清掉 Gatekeeper 标记后启动，给不熟悉右键打开的人用
    └── 使用说明.md

刻意不放的内容：原始素材（几十 MB 且不宜外传）、归档、tools/tests 等工程文件。
给普通朋友的就是"双击能用"三件套。

压缩用 ditto 而不是 zip：ditto 更擅长处理 bundle，能保住可执行位。
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys

CODE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # code/
ROOT = os.path.dirname(CODE)                                          # 仓库根
APP = os.path.join(CODE, "build", "dist", "PopoHere.app")
RELEASES = os.path.join(CODE, "build", "releases")

LAUNCHER = """#!/bin/bash
# 双击即可启动 PopoHere。
#
# 它做两件事：清掉 macOS 给网络下载文件打的"隔离标记"，然后打开 PopoHere.app。
# 本机首次需要右键本文件 → 打开（同样是因为没有付费签名），之后就能直接双击。
#
# 本文件必须和 PopoHere.app 放在同一个文件夹里。

cd "$(dirname "$0")"
APP="$PWD/PopoHere.app"

if [ ! -d "$APP" ]; then
    echo "找不到 PopoHere.app。"
    echo "请确保它和本脚本在同一个文件夹里。"
    exit 1
fi

xattr -dr com.apple.quarantine "$APP" 2>/dev/null
echo "启动 PopoHere…"
open "$APP"
"""


def app_version() -> str:
    plist = os.path.join(APP, "Contents", "Info.plist")
    with open(plist, "rb") as f:
        return plistlib.load(f).get("CFBundleShortVersionString", "0.0.0")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", help="覆盖版本号，默认读 Info.plist")
    args = ap.parse_args()

    if not os.path.isdir(APP):
        print(f"缺少 {APP}，先跑 ./code/build/build_app.sh", file=sys.stderr)
        return 1

    ver = args.version or app_version()
    name = f"PopoHere-v{ver}"
    stage = os.path.join(RELEASES, "stage", name)
    if os.path.exists(stage):
        shutil.rmtree(stage)
    os.makedirs(stage)

    subprocess.run(["ditto", APP, os.path.join(stage, "PopoHere.app")], check=True)

    launcher = os.path.join(stage, "启动 PopoHere.command")
    with open(launcher, "w", encoding="utf-8") as f:
        f.write(LAUNCHER)
    os.chmod(launcher, 0o755)

    manual = os.path.join(ROOT, "doc", "usage_zh.md")
    if os.path.exists(manual):
        shutil.copy2(manual, os.path.join(stage, "使用说明.md"))
    else:
        print("警告：没有 使用说明.md，包里会缺少说明文档", file=sys.stderr)

    os.makedirs(RELEASES, exist_ok=True)
    zpath = os.path.join(RELEASES, name + ".zip")
    if os.path.exists(zpath):
        os.remove(zpath)
    # 不加 --sequesterRsrc：包内没有 resource fork，加了反而会多出一个 __MACOSX 目录
    subprocess.run(["ditto", "-c", "-k", "--keepParent", stage, zpath], check=True)

    size_kb = os.path.getsize(zpath) / 1024
    print(f"生成 {zpath}  ({size_kb:.0f} KB)")
    print("包内容：")
    for root, dirs, files in os.walk(stage):
        dirs.sort()
        for fn in sorted(files):
            p = os.path.join(root, fn)
            print(f"  {os.path.relpath(p, stage)}")
    shutil.rmtree(os.path.join(RELEASES, "stage"), ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
