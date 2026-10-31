#!/bin/bash
# 构建 PopoHere.app
#   ./code/build/build_app.sh            # 构建 code/build/dist/PopoHere.app
#   ./code/build/build_app.sh --run      # 构建后直接启动
#
# 产物说明：
#   - 二进制是 x86_64 + arm64 通用包，Intel / Apple 芯片的 Mac 都能跑
#   - index.html 已把素材全部 base64 内嵌，包内不再放一份拷贝
#   - 构建末尾做 ad-hoc 重新签名并校验，避免"应用已损坏"
set -euo pipefail

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"          # code/build
CODE_DIR="$(dirname "$BUILD_DIR")"                  # code
ROOT="$(dirname "$CODE_DIR")"                       # 仓库根

APP="$BUILD_DIR/dist/PopoHere.app"
CONTENTS="$APP/Contents"
SHELL_DIR="$CODE_DIR/core/func_window"
SOURCES=(
  "$SHELL_DIR/PHMain.m"
  "$SHELL_DIR/PHPanel.m"
  "$CODE_DIR/core/func_reminder/PHReminder.m"
  "$CODE_DIR/core/func_reminder/PHAlert.m"
  "$CODE_DIR/core/func_checklist/PHChecklist.m"
)
INCLUDES=(-I "$SHELL_DIR" -I "$CODE_DIR/core/func_reminder" -I "$CODE_DIR/core/func_checklist")

echo "==> 1/4 生成 Web 资源（原生模式）"
python3 "$BUILD_DIR/build_web.py" --native

echo "==> 2/4 编译 Objective-C 外壳（通用二进制）"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/app"
for ARCH in arm64 x86_64; do
    clang -fobjc-arc -O2 -Wall -Wno-deprecated-declarations -arch "$ARCH" \
        -framework Cocoa -framework WebKit \
        "${INCLUDES[@]}" "${SOURCES[@]}" -o "$CONTENTS/MacOS/PopoHere-$ARCH"
done
lipo -create -output "$CONTENTS/MacOS/PopoHere" \
    "$CONTENTS/MacOS/PopoHere-arm64" "$CONTENTS/MacOS/PopoHere-x86_64"
rm -f "$CONTENTS/MacOS/PopoHere-arm64" "$CONTENTS/MacOS/PopoHere-x86_64"

echo "==> 3/4 组装 app 包"
cp "$SHELL_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$BUILD_DIR/out/native.html" "$CONTENTS/Resources/app/index.html"
cp "$CODE_DIR/core/func_menu/panel.html" "$CONTENTS/Resources/app/panel.html"
# 菜单栏图标：cutout.py 已裁到内容并做成模板图标（pet_images 里的是 640 画布，会变成一个小点）
cp "$CODE_DIR/pet_others/tray_icon.png" "$CONTENTS/Resources/tray_icon.png"
cp "$CODE_DIR/pet_others/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# 清除隔离属性，避免本机首次打开被 Gatekeeper 拦
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> 4/4 重新签名并校验"
codesign --force --deep --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed -n '1,3p'

echo "完成：$APP"
du -sh "$APP"
lipo -info "$CONTENTS/MacOS/PopoHere" | sed 's/^/二进制：/'

if [[ "${1:-}" == "--run" ]]; then
  echo "启动 PopoHere…"
  open "$APP"
fi
