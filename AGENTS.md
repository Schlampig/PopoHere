# AGENTS.md

给接手这个项目的 AI（或未来的自己）看的速查文档。读这一份就能上手。

## 项目是什么

以用户自家猫 Popo 的照片为素材做的 **macOS 桌面宠物**。纯本地运行、零外部 API、完全无声。
v1.0 已完成并开源，v2.0 正在规划（见 `doc/PRD/PRD.md`）。

- 仓库：<https://github.com/Schlampig/PopoHere>（当前 private，目标是转 public）
- 主分支 `main`，remote 已配好，本机装了 osxkeychain 凭据，可直接 push
- 提交署名走 GitHub 匿名邮箱（`16538895+Schlampig@users.noreply.github.com`），**不会泄露真实邮箱**

## 提交约定

用户已经把这项目的版本提交交给 AI 负责。每次迭代后：

```bash
git add -A
git commit -m "type: 一句话说明"
git push
```

- commit message 用 `feat:` / `fix:` / `docs:` / `refactor:` / `chore:` 前缀
- 提交前**务必**跑测试（见下）并 `git status` 确认没把 `code/build/` 的产物带进去
- 不要提交 `.workbuddy/`、`.wbapp_*.genie`（已在 `.gitignore` 里，含本机绝对路径）

## 当前进度（v2.0）

| 环节 | 状态 |
|---|---|
| 素材预处理 | ✅ `code/prepare/cutout.py` + `build_theme.py`（扫文件名生成 theme.json） |
| 状态机 | ✅ 7 常规 + 2 过渡状态，36 条断言 |
| 拖拽跟手 | ✅ 原生屏幕坐标跟踪，7 条断言 |
| 渲染 / 输入 / 菜单 | ✅ `func_*` 模块化 |
| 玻璃菜单 + 状态面板 | ✅ `PHPanel` + `panel.html`（NSVisualEffectView 毛玻璃） |
| 定时提醒 / 待办清单 | ✅ `func_reminder` / `func_checklist` |
| 原生外壳 | ✅ 多模块编译，通用二进制 |
| **真机视觉验证** | ⚠️ 见下方「未验证项」 |

### 未验证项（下次接手必看）

本次开发所在会话**无法截取到 GUI 窗口**：`screencapture` 能拍到桌面壁纸和菜单栏，
但 agent 启动的窗口（包括一个最小 WKWebView 测试程序）都不会出现在截图里；
而 `CGWindowListCopyWindowInfo` 显示窗口 `onscreen=1`、`alpha=1`、页面 `didFinishNavigation` 正常触发。
判断是会话/窗口服务器的隔离，不是代码问题——但**毛玻璃面板的实际观感、右键弹菜单的位置、
状态面板的拖动手感，都还没被人工确认过**。拿到真实桌面后请优先验这三点。

### 素材现状：⏸ 等用户拍真图（v2.0 代码已完工）

`code/pet_images/` 里是**占位素材**（`make_placeholder_assets.py` 复制现有图生成，
31 个引用只有 7 张不同）。用户会按 PRD 拍完整素材后一次性替换。

**替换时的固定流程**（顺序不能换）：

```bash
python3 code/prepare/cutout.py --check      # 1. 先只校验命名，不跑模型
python3 code/prepare/cutout.py              # 2. 抠图 → 覆盖 code/pet_images/
python3 code/prepare/build_theme.py         # 3. 扫文件名生成 theme.json
rm code/prepare/make_placeholder_assets.py  # 4. 删掉占位脚本
python3 code/build/build_web.py && ./code/build/build_app.sh   # 5. 重建
node code/test/state_machine_test.js && python3 code/test/click_mash_test.py \
  && python3 code/test/drag_tracking_test.py                   # 6. 三条测试要全绿
```

替换后要重点手测：**各状态切换会不会"跳"（体型/地面线对不上）**、
**同状态多帧之间的呼吸感**、**挠人/被撸是否终于长得不一样了**。

## 目录布局

```
source/origin_images/     用户原始照片（仓库自带一份 demo：就是 Popo 本人）
source/origin_audios/     预留，可为空
code/prepare/             预处理脚本：原始照片 → 可用贴图
code/pet_images/          处理后的贴图 + theme.json（状态↔贴图的契约）
code/pet_audios/          预留，可为空
code/pet_others/          应用图标、菜单栏图标
code/core/                桌宠本体（只跟功能有关，与造型无关）
  main.js                   装配 + 主循环 + window.App 对外 API
  func_state/               状态机（纯逻辑，不碰 DOM → 可以被 Node 直接测）
  func_render/              状态 → 贴图 / 动效 / 气泡
  func_input/               命中判定、单击 vs 拖拽
  func_menu/                右键菜单桥 + panel.html（玻璃面板 UI）
  func_reminder/            定时提醒（ObjC，NSUserDefaults 持久化）
  func_checklist/           待办清单（ObjC，JSON 持久化）
  func_window/              AppKit 外壳：窗口 / 菜单栏 / 拖拽 / 面板窗口
code/build/               构建与打包脚本 + 产物（产物 gitignore）
code/test/                测试
code/prototype/           HTML 外壳模板（CSS + DOM）
doc/PRD/PRD.md            产品需求（当前版本）
doc/ARCHITECTURE.md       架构与踩坑（改代码前读）
doc/usage_zh.md           给最终用户的中文说明（打包时复制进 zip）
doc/README_en.md          README 英文版
```

**根目录只放**：`README.md`、`AGENTS.md`、`LICENSE`、`.gitignore`，以及三个目录 `source/ code/ doc/`。
新增文件请按这个分层放，不要往根目录堆。

## 常用命令

```bash
# 预处理（素材有更新时；--check 只校验命名不跑模型）
python3 code/prepare/cutout.py
python3 code/prepare/cutout.py --check

# 扫文件名生成 theme.json（加减素材后必跑）
python3 code/prepare/build_theme.py

# 研发期占位素材（正式素材到位后删除这个脚本）
python3 code/prepare/make_placeholder_assets.py

# 生成预览页（改了 core/ 或 prototype/ 之后）
python3 code/build/build_web.py
open code/build/out/preview.html          # 浏览器里带调试面板

# 测试（改了状态机 / 输入 必跑，三条都要绿；后两条需要本机有 Google Chrome）
node code/test/state_machine_test.js      # 60 条，纯逻辑
python3 code/test/click_mash_test.py      # 9 条，连点翻脸（跑真实产物 + DOM 事件）
python3 code/test/drag_tracking_test.py   # 7 条，拖拽跟手

# 重新生成应用图标
python3 code/build/make_icon.py

# 构建 app（通用二进制 + ad-hoc 重签名 + 校验）
./code/build/build_app.sh
./code/build/build_app.sh --run

# 端到端自检（约 14s，结果在 stderr）：
#   右键→menu → 进定时提醒(reminders) → 点猫收起 → 再右键应回到 menu
#   → 预览 sleep → 应回 menu → 收起 → 提醒阶梯 1/5/10/15/20/15/10/5/1
POPOHERE_QA_SEQ=1 code/build/dist/PopoHere.app/Contents/MacOS/PopoHere 2>&1 | grep "\[QA\]"

# 打包发布 zip
python3 code/build/package_release.py
```

## 关键决策（别改回去）

### 1. 技术栈：AppKit + WKWebView，不是 Swift，不是 PySide6

PRD 原本定 Python + PySide6，但 pip 装不上（环境 bulk-install guard 拦截）；Swift 工具链也不可用（只装了 Command Line Tools，`swiftc` 报 `redefinition of module 'SwiftBridging'`）。
`clang + Objective-C + WebKit` 是唯一能编译、零依赖、体积最小的路线。已跑通，别折腾迁移。

### 2. 拖拽必须由原生层用屏幕坐标驱动

JS 用 `clientX` 算位移 + `postMessage` 移动窗口会形成**坐标系反馈环**（视口随窗口移动，delta 被自己抵消），表现为剧烈抖动。
现在：`NSEvent` 本地监视器 + `[NSEvent mouseLocation]` 同步 `setFrameOrigin`；JS 只用 `screenX/screenY` 做阈值判定。
完整分析见 `doc/ARCHITECTURE.md`。**改拖拽前先跑 `drag_tracking_test.py`**。

### 3. `dragging` 状态的 motion 必须是 `none`

早期用 `float`（±8px 漂浮 + ±3° 旋转），猫在手里一直晃，和"指哪打哪"冲突。

### 4. 状态机不碰 DOM

`func_state/state_machine.js` 是唯一的纯逻辑层，Node 直接跑测试。引入 DOM 依赖会毁掉这个能力。

### 5. 贴图在构建期内联成 base64

`.app` 包里不存 `pet_images` 副本。早期版本两份并存，白胖 3.7MB。

## theme.json 契约

- `states.<name>.visuals`：数组，进入状态时**等概率随机抽 1 张并锁定**，离开再进才重抽
- `loop` + `duration`：`duration` 是非循环状态的停留秒数
- `motion`：本项目新增字段，`none / breathe / breathe-slow / bob-walk / shake / float / drop`（CSS 动画，省掉逐帧素材）
- `bubble`：可选 emoji 字符串（PRD 原设想气泡 PNG，改用 emoji 少一堆素材）
- `hitBoxes`：相对比例，**原点在图片左上角**（PRD 示例用的是左下原点，此处有意不同）

## 状态机规则（v2.0）

1. 状态：`idle` / `touch` / `scratch` / `play` / `sleep` / `dragging` / `menu` + `startled` / `landed`
2. **所有"播完"只有一个出口 `_rest()`**：`menuOpen ? menu : idle`。任何 `_goto('idle')` 的
   写法都会重新引入"面板还开着、猫已经在 idle 起步"的 bug。`menuOpen` 只由外壳在面板
   `show` / `hide` 回调里写入（`App.menuOpened()` / `App.menuClosed()`）
3. 离开 `menu` 时外壳必须收起面板：`main.js` 的 `onTransition` 会发 `menuPanelClose`。
   不能只靠"面板失焦自己隐藏"——点猫时状态可能先走、面板还留着
4. 状态面板点状态名 = `preview()`：只演一遍、不写连撸计数，演完走 `_rest()`；
   预览期间**不能**触发 `menuPanelClose`（菜单要开着让人逐个试）
5. `startled` 只能从 `sleep` 被点击/拖拽时进入；睡中被拖 → `startled` 播完若手还按着 → `dragging`
6. `dragging` 是跨状态模态行为，释放后进 `landed`，不回原状态
7. `play` 被点击 → 直接回 `idle`（打断），**不**进入 `touch`
8. `menu` 开着时 `idle` 不分流（不会溜达/睡着）；兜底超时 `menu_timeout_sec`（120s）
   触发时同时清 `menuOpen`，否则 `_rest()` 会又回到 menu，永远出不来
9. 单击判定：位移 < `click_max_drift_px`（**12**，与外壳 `kDragThreshold` 一致）**且** 时长 < 300ms
10. 连撸：进入 `touch` 时按 `touch_repeat_window_sec`（4s）累计 `touchStreak`，
    达 `touch_scratch_threshold`（10）**当场**转 `scratch`，不等 touch 播完；
    `scratch` 后冷却 6s，期间不翻脸
11. `touch` 播放中继续点击 = 重播并 +1 连击；`startled` / `landed` 里的点击也计数
    （否则一轮猛点会被过渡动画吃掉大半，用户以为坏了）
12. 坑：连击必须在「进入 touch 那一刻」算间隔，不能在结束时算
13. 坑：`click_max_drift_px` 曾是 5px，实测连点时手抖 6–10px 就会判成拖拽，
    于是每一下都变成 `dragging → landed → idle`，计数永远是 0 —— 别调回去

## 已知短板

1. **占位素材**：31 个引用只有 7 张不同图，被撸/挠人/静息看着几乎一样（等真图）
2. **每状态只有 1 帧**，没有真正的多帧动画；`fps/loop` 已经支持，缺的是图
3. **素材内联进 HTML**：换图必须重跑构建，不能运行时替换（v1.0 提过，仍未做）
4. **声音菜单是灰的**：`code/pet_audios/` 与 `source/origin_audios/` 已预留，尚无音频
5. **没有 Apple 公证**：别人首次打开要右键 →「打开」
6. **v3 迷宫未做**：`code/core/func_*` 目录结构已就绪，加模块不用动别的

> 已解决、别再写进短板：开机自启（LaunchAgent 已实现）、hitbox 偏移（v2.0 合并成单一 body）

## 环境踩坑

- **git push 报 `CONNECT tunnel failed, 502` 不是仓库配置问题**：会话环境会注入
  `HTTPS_PROXY=http://127.0.0.1:49360`，它对 github.com 返回 502，而
  `curl --noproxy '*' https://github.com` 直连是 200。推法：
  `env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy -u ALL_PROXY git push`
- **改 `defaults` 前先 `pkill`**：旧实例退出时会把内存里的旧偏好刷回去覆盖你的修改
- **macOS 自带 grep 是 BSD 版，BRE 不支持 `\|`**：`grep "a\|b"` 会被当字面量、静默无匹配。用 `-E`
- **合成鼠标事件注入不进来**：本机没有进程被授予辅助功能权限（`AXIsProcessTrusted` = NO），`CGEventPost` 的事件会被丢弃 → 手感类问题只能让用户手测
- `screencapture` 缺屏幕录制权限写不了盘；`log show` 也读不到本进程日志 → 验证 GUI 靠 `pgrep` + `defaults read com.popohere.pet`
- headless Chrome 里页面被当作后台标签，`setInterval` / `rAF` 会被节流 → 自动化测试别读 DOM 上的状态文字（永远陈旧），直接调 `window.App.state()`
- `const` 声明的顶层变量不在 `window` 上（`POPO_THEME` 要裸引用）
- 用 shell 创建/改动 `.app` 目录偶发被沙箱拦；用 Python 的 `os.makedirs`/`shutil` 组装可绕过
- `codesign` 必须在包组装完成**之后**执行，否则报 "code has no resources but signature indicates they must be present"
- `ditto` 打包别加 `--sequesterRsrc`（会多出 `__MACOSX`）
- 可用的验证手段：headless Chrome 截图 / `--dump-dom` 跑页面内断言
  `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir=/tmp/x --dump-dom file://...`

## 文档索引

| 文档 | 读者 |
|---|---|
| `README.md` | 仓库门面：产品介绍 + 用法 + DIY 指南 |
| `doc/README_en.md` | 英文版 README |
| `doc/PRD/PRD.md` | 产品需求（最新版本） |
| `doc/ARCHITECTURE.md` | 开发者：架构、数据流、踩坑 |
| `doc/usage_zh.md` | 最终用户：安装与玩法（会打进 zip） |
| `AGENTS.md` | 本文件，AI 接手入口 |
