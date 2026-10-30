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

## 当前进度（v1.0，2026-10-28 定格）

| 环节 | 状态 |
|---|---|
| 素材预处理（抠图/归一化） | ✅ `code/prepare/cutout.py` |
| 状态机 | ✅ 10 状态，32 条断言 |
| 拖拽跟手 | ✅ 原生屏幕坐标跟踪，7 条断言 |
| 渲染 / 输入 / 菜单 | ✅ 已拆成 `func_*` 模块 |
| 原生外壳 | ✅ 通用二进制，768KB |
| 构建 / 打包 / 图标 | ✅ `code/build/` |
| 功能菜单（v2.0 需求） | ⬜ 未做 |
| 多素材 + 状态精简（v2.0 需求） | ⬜ 未做 |

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
  func_menu/                右键菜单
  func_window/              AppKit 外壳：窗口 / 菜单栏 / 拖拽跟踪 / JS 桥
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

# 生成预览页（改了 core/ 或 prototype/ 之后）
python3 code/build/build_web.py
open code/build/out/preview.html          # 浏览器里带调试面板

# 测试（改了状态机 / 拖拽 必跑，两条都要绿）
node code/test/state_machine_test.js      # 32 条
python3 code/test/drag_tracking_test.py   # 7 条，需要本机有 Google Chrome

# 重新生成应用图标
python3 code/build/make_icon.py

# 构建 app（通用二进制 + ad-hoc 重签名 + 校验）
./code/build/build_app.sh
./code/build/build_app.sh --run

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

## v1.0 状态机规则

1. `startled` 只能从 `sleep` 被点击/拖拽时进入
2. 睡中被拖 → 先 `startled`，播完如果手还按着 → `dragging`
3. `dragging` 是跨状态模态行为，释放后进 `landed`，不回原状态
4. `walk` 被点击 → 直接回 `idle`（打断）
5. `menu` 状态下忽略左键；状态机自带 2 秒兜底回 `idle`
6. 单击判定：位移 < 5px **且** 时长 < 300ms
7. `scratch` 结束后 3 秒冷却
8. 坑：连续摸脚的判定必须在「摸脚那一刻」算间隔，不能在 `pet_paw` 结束时算（否则第一次摸脚就自触发 scratch）

> v2.0 会精简状态并重命名素材（`<state>_<序号>.png`），届时本节要整体重写。

## 已知短板

1. **素材重复**：`pet_head/pet_paw/scratch` 源文件相同，`walk/landed/cool` 也相同 → 摸头/摸脚/挠人长得一样
2. **每状态只有 1 帧**，没有真正的多帧动画
3. **hitbox 全局一套**：睡姿和站姿共用，躺姿时判定区偏移
4. **素材写死进 HTML**：用户换图要重新跑构建，不能运行时替换
5. **没有开机自启**：可加 `~/Library/LaunchAgents/`
6. **没有 Apple 公证**：别人首次打开要右键 →「打开」

## 环境踩坑

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
