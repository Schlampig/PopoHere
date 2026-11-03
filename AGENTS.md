# AGENTS.md

给接手这个项目的开发者（或协助开发的 AI）看的速查文档。读这一份就能上手。

## 项目是什么

以真实猫咪照片为素材做的 **macOS 桌面宠物**。纯本地运行、零外部 API、完全无声。
当前版本 v2.0，仓库已公开。

- 仓库：<https://github.com/Schlampig/PopoHere>
- 主分支 `main`，推送凭据由本机凭证管理器提供，无需在仓库中配置
- **提交署名请使用 GitHub 匿名邮箱机制**（GitHub 设置中开启 *Keep my email addresses private*），
  不要在配置里写真实邮箱，也不要把邮箱地址提交进任何文件

## 提交约定

版本提交由维护者统一负责。每次迭代后：

```bash
git add -A
git commit -m "type: 一句话说明"
git push
```

- commit message 用 `feat:` / `fix:` / `docs:` / `refactor:` / `chore:` 前缀
- 提交前**务必**跑测试（见下）并 `git status` 确认没有把 `code/build/` 的产物带进去
- 不要提交本地工具生成的目录与临时文件（已在 `.gitignore` 中列出）
- 提交前检查 diff 中不含个人路径、邮箱、凭据或其它与本项目无关的信息

## 当前进度（v2.0）

| 环节 | 状态 |
|---|---|
| 素材预处理 | ✅ `code/prepare/cutout.py` + `build_theme.py`（扫文件名生成 theme.json） |
| 状态机 | ✅ 7 常规 + 2 过渡状态，58 条断言 |
| 拖拽跟手 | ✅ 原生屏幕坐标跟踪，7 条断言 |
| 渲染 / 输入 / 菜单 | ✅ `func_*` 模块化 |
| 玻璃菜单 + 状态面板 | ✅ `PHPanel` + `panel.html`（NSVisualEffectView 毛玻璃） |
| 定时提醒 / 待办清单 | ✅ `func_reminder` / `func_checklist` |
| 原生外壳 | ✅ 多模块编译，通用二进制 |
| 到点提醒弹窗 | ✅ `func_reminder/PHAlert`（右上角玻璃窗 / 10s 倒计时 / 确认 / **多条叠放**） |
| 提醒模式 | ✅ 每条「一次 / 间隔」，默认一次；一次响过自动关闭 |
| 视觉与交互验证 | ✅ 已由维护者多轮人工测试确认 |

## 素材现状

仓库内 `source/origin_images/` 只保留**每个状态的第一张原图**（9 个状态 + `logo_1` + `menubar_1`），
作为示例与 DIY 的起点；其余素材与全部原始照片留在本地。

`code/pet_images/` 中保留了完整的 16 张贴图与 `theme.json`，因此仓库克隆下来即可构建运行。

**换素材的固定流程**（顺序不能换）：

```bash
python3 code/prepare/cutout.py --check      # 1. 先只校验命名，不跑模型
python3 code/prepare/cutout.py              # 2. 抠图 → 覆盖 code/pet_images/
python3 code/prepare/build_theme.py         # 3. 扫文件名生成 theme.json
python3 code/build/build_web.py && ./code/build/build_app.sh   # 4. 重建
node code/test/state_machine_test.js && python3 code/test/click_mash_test.py \
  && python3 code/test/drag_tracking_test.py                   # 5. 三条测试要全绿
```

> 注意：`cutout.py` 会删除 `code/pet_images/` 中不再对应任何原图的贴图。
> 只用仓库自带的示例素材跑一遍，会覆盖掉多帧贴图；需要恢复时执行 `git checkout code/pet_images`。

预处理有两条"隐形规则"，改脚本前务必知道：

- **同状态按视觉面积归一**（`harmonize()`）：同状态的几帧只缩不放，缩到偏小的中位数，
  否则躺着和坐着的两帧看着像忽大忽小。实测同状态一致度 0.97–1.00（归一前 0.83–0.91）
- **不旋转、不翻转任何素材**：照片方向即最终显示方向。这是刻意的取舍——
  自动纠正会替使用者做出错误判断（曾有一张竖图被转成横向，身体朝向明显不自然），
  已删除相关机制，**不要重新引入**；方向问题写进 `doc/UserGuide.md` 由使用者自行处理

替换后要重点手测：**各状态切换会不会"跳"**、**同状态多帧的呼吸感**、**挠人与被撸是否有区别**。

## 目录布局

```
source/origin_images/     原始照片（仓库自带每个状态的第一张作为示例）
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
  func_reminder/            定时提醒（PHReminder 计时 + PHAlert 到点弹窗）
  func_checklist/           待办清单（ObjC，JSON 持久化）
  func_window/              AppKit 外壳：窗口 / 菜单栏 / 拖拽 / 面板窗口
code/build/               构建与打包脚本 + 产物（产物 gitignore）
code/test/                测试
code/prototype/           HTML 外壳模板（CSS + DOM）
doc/UserGuide.md          用户指南（使用 + 自己制作，打包时复制进 zip）
doc/UserGuide_en.md       英文版用户指南
doc/README_en.md          README 英文版
doc/PRD/                  历次 PRD（PRD_v<版本>_<日期>）
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

# 生成预览页（改了 core/ 或 prototype/ 之后）
python3 code/build/build_web.py
open code/build/out/preview.html          # 浏览器里带调试面板

# 测试（改了状态机 / 输入 / 提醒 必跑；后两条需要本机有 Google Chrome）
node code/test/state_machine_test.js      # 58 条，纯逻辑
python3 code/test/click_mash_test.py      # 9 条，连点翻脸（跑真实产物 + DOM 事件）
python3 code/test/drag_tracking_test.py   # 7 条，拖拽跟手
clang -fobjc-arc -framework Foundation -I code/core/func_reminder \
  code/test/reminder_store_test.m code/core/func_reminder/PHReminder.m \
  -o /tmp/remtest && /tmp/remtest          # 16 条，提醒存储/计时语义

# 重新生成应用图标
python3 code/build/make_icon.py

# 构建 app（通用二进制 + ad-hoc 重签名 + 校验）
./code/build/build_app.sh
./code/build/build_app.sh --run

# 打包发布 zip（产物在 code/build/releases/）
python3 code/build/package_release.py
```

## 关键决策（别改回去）

### 1. 技术栈：AppKit + WKWebView，不是 Swift，不是 PySide6

PRD 原本计划 Python + PySide6，但 PySide6 的依赖树在受限环境中无法安装；
Swift 工具链也不可用（仅有 Command Line Tools，`swiftc` 报
`redefinition of module 'SwiftBridging'`）。
`clang + Objective-C + WebKit` 是唯一能编译、零第三方依赖、体积最小的路线。
已跑通并有完整测试覆盖，不要迁移。

### 2. 拖拽必须由原生层用屏幕坐标驱动

JS 用 `clientX` 算位移 + `postMessage` 移动窗口会形成**坐标系反馈环**
（视口随窗口移动，位移被自己抵消），表现为剧烈抖动。
现在：`NSEvent` 本地监视器 + `[NSEvent mouseLocation]` 同步 `setFrameOrigin`；
JS 只用 `screenX / screenY` 做阈值判定。
完整分析见 `doc/UserGuide.md` 的「拖拽：一个必须注意的坐标系问题」。
**改拖拽前先跑 `drag_tracking_test.py`**。

### 3. `dragging` 状态的 motion 必须是 `none`

使用 `float`（±8px 漂浮 + ±3° 旋转）会让桌宠在手中持续晃动，与"指哪打哪"直接冲突。

### 4. 状态机不碰 DOM

`func_state/state_machine.js` 是唯一的纯逻辑层，Node 可直接跑测试。
引入 DOM 依赖会破坏这个能力。

### 5. 贴图在构建期内联成 base64

`.app` 包内不再保存一份 `pet_images` 副本；两份并存会使体积增加约 3.7 MB。

## theme.json 契约

- `states.<name>.visuals`：数组，进入状态时**等概率随机抽 1 张并锁定**，离开再进才重抽
- `loop` + `duration`：`duration` 是非循环状态的停留秒数
- `motion`：`none / breathe / breathe-slow / bob-walk / shake / float / drop`（CSS 动画，省掉逐帧素材）
- `bubble`：可选文案，支持 `bubble`（单条）与 `bubbles`（数组，随机取一条）
- `hitBoxes`：相对比例，**原点在图片左上角**（PRD 早期示例用的是左下原点，此处有意不同）

## 提醒模型（func_reminder）

| 字段 | 含义 |
|---|---|
| `name` | 面板里显示的名字（摸鱼 / 喝水 / 久坐拉伸） |
| `message` | 弹窗整句，不含倒计时（`摸鱼结束，接着干活~`） |
| `minutes` | 间隔，永远落在 1 或 5 的倍数上 |
| `enabled` | 总开关；**一次性提醒响完会自动置 NO** |
| `repeat` | YES=间隔循环，NO=一次性 |

- `tick` 每秒推进，**一轮只返回一个到点项**（同时到点的下一秒补上，正好叠成两条）
- 多条提醒叠在同一个面板里，各自倒计时；全部关完才收面板
- 测试用独立 `NSUserDefaults` suite（`initWithDefaults:`），不要用 standardUserDefaults，
  否则会污染使用者的真实配置

## 状态机规则（v2.0）

1. 状态：`idle` / `touch` / `scratch` / `play` / `sleep` / `dragging` / `menu` + `startled` / `landed`
2. **所有"播完"只有一个出口 `_rest()`**：`menuOpen ? menu : idle`。任何 `_goto('idle')` 的
   写法都会破坏"菜单面板与 menu 状态同生共死"的约束。`menuOpen` 只由外壳在面板
   `show` / `hide` 回调里写入（`App.menuOpened()` / `App.menuClosed()`）
3. 离开 `menu` 时外壳必须收起面板：`main.js` 的 `onTransition` 会发 `menuPanelClose`。
   不能只靠"面板失焦自己隐藏"——点击桌宠时状态可能先走、面板还留着
4. 状态面板点状态名 = `preview()`：只演一遍、不写连撸计数，演完走 `_rest()`；
   预览期间**不能**触发 `menuPanelClose`（菜单需要保持打开，供逐个查看）
5. `startled` 只能从 `sleep` 被点击/拖拽时进入；睡中被拖 → `startled` 播完若手还按着 → `dragging`
6. `dragging` 是跨状态模态行为，释放后进 `landed`，不回原状态
7. `play` 被点击 → 直接回 `idle`（打断），**不**进入 `touch`
8. `menu` 开着时 `idle` 不分流（不会溜达/睡着）；兜底超时 `menu_timeout_sec`（120s）
   触发时同时清 `menuOpen`，否则 `_rest()` 会又回到 menu，永远出不来
9. 单击判定：位移 < `click_max_drift_px`（**12**，与外壳 `kDragThreshold` 一致）**且** 时长 < 300ms
10. 连续抚摸：进入 `touch` 时按 `touch_repeat_window_sec`（4s）累计 `touchStreak`，
    达 `touch_scratch_threshold`（10）**当场**转 `scratch`，不等 touch 播完；
    `scratch` 后冷却 6s，期间不翻脸
11. `touch` 播放中继续点击 = 重播并 +1；`startled` / `landed` 里的点击也计数
    （否则连续点击会被过渡动画吞掉大半）
12. 计数间隔必须在「进入 touch 那一刻」计算，不能在结束时计算
13. `click_max_drift_px` 不能用 5px：连续点击时手部抖动常在 6–10px，
    会被判成拖拽，于是每一下都变成 `dragging → landed → idle`，计数永远为 0

## 已知短板

1. **每状态只有 1 张图时缺动画感**：`fps` / `loop` 已支持多帧，缺的是素材
2. **素材内联进 HTML**：换图必须重跑构建，不能运行时替换
3. **声音菜单是灰的**：`code/pet_audios/` 与 `source/origin_audios/` 已预留，尚无音频
4. **没有 Apple 公证**：首次打开需右键 →「打开」
5. **v3 迷宫未做**：`code/core/func_*` 目录结构已就绪，加模块不用动其它代码

> 已解决、不必再列为短板：开机自启（LaunchAgent 已实现）、命中区偏移（合并为单一 body）

## 环境与踩坑

- **git push 报 `CONNECT tunnel failed, 502` 或 `Empty reply from server`**：
  通常是本地代理对 github.com 的转发异常。可绕开代理重试：
  `env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy git push`
- **改 `defaults` 前先 `pkill`**：旧实例退出时会把内存中的旧偏好刷回磁盘，覆盖你的修改
- **macOS 自带 grep 是 BSD 版，BRE 不支持 `\|`**：`grep "a\|b"` 会被当字面量、静默无匹配。用 `-E`
- **合成鼠标事件需要辅助功能授权**：未授权时 `CGEventPost` 的事件会被系统丢弃，
  因此拖拽手感这类问题只能由人工验证
- **headless Chrome 中页面被视为后台标签**：`setInterval` / `requestAnimationFrame` 会被节流，
  自动化测试不要读 DOM 上的状态文字（永远是陈旧值），直接调用 `window.App.state()`
- **`const` 声明的顶层变量不在 `window` 上**：`POPO_THEME` 等需要裸引用
- **`codesign` 必须在包组装完成之后执行**，否则报
  "code has no resources but signature indicates they must be present"
- **`ditto` 打包不要加 `--sequesterRsrc`**（会多出 `__MACOSX` 目录）
- **验证前端改动的可行手段**：headless Chrome 截图或 `--dump-dom` 跑页面内断言

## 文档索引

| 文档 | 读者 |
|---|---|
| `README.md` | 仓库门面：产品介绍 + 用法 + 改造入口 |
| `doc/README_en.md` | 英文版 README（与中文版逐段对应） |
| `doc/UserGuide.md` | 用户指南：安装 / 互动 / 功能 / 自己做一只 |
| `doc/UserGuide_en.md` | 英文版用户指南 |
| `doc/PRD/PRD_v2_261030.md` | 当前版本的产品需求 |
| `doc/PRD/PRD_v1_261027.md` | v1.0 的 PRD（留档） |
| `AGENTS.md` | 本文件，接手入口 |

> `doc/CHANGELOG.md` 只在本地维护，已加入 `.gitignore`，不随仓库发布。
