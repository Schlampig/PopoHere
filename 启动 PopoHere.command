#!/bin/bash
# 双击即可打开 Popo。
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -d "$DIR/dist/PopoHere.app" ]; then
    echo "找不到 dist/PopoHere.app，请先运行 ./native/build.sh"
    exit 1
fi
open "$DIR/dist/PopoHere.app"
