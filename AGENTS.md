# AGENTS.md

给后续接手这个项目的 AI（或未来的自己）看的速查文档。读这一份就够了。

## 项目是什么

以用户自家猫 Popo 的照片为素材做的 **macOS 桌面宠物**。纯本地运行、零外部 API、完全无声。

- 工作区根目录：`/Users/pigpigbear/zyjProjects/Just_for_Fun/PopoHere`
- `素材/` 与 `归档/` 为**只读**素材源，**绝对不要改动**，也不要外传（打包时排除）
- 根目录 `PRD.md` 是产品需求原文

## 当前进度（2026-10-28）

| 环节 | 状态 | 说明 |
|---|---|---|
| 抠图出透明素材 | ✅ 完成 | rembg/u2net，`tools/cutout.py` → `themes/popo/*.png`（640×640，底部对齐） |
| theme.json 契约 | ✅ 完成 | 11 个字段齐全，见下文 |
| HTML 原型 | ✅ 完成 | 带调试面板，可现场验证状态机手感 |
| 状态机逻辑 | ✅ 完成 + 测试 | `node tests/state_machine_test.js`，32 条断言全通过 |
| 拖拽手感 | ✅ 已修复 | 见下方「拖拽为什么会抖」，**动这部分之前务必先读** |
| 正式版桌宠 | ✅ 可运行 | `dist/PopoHere.app`，768KB，通用二进制（x86_64 + arm64） |
| 应用图标 | ✅ 完成 | `tools/make_icon.py` 从 `landed.png` 生成 `assets/AppIcon.icns` |
| 打包分发 | ✅ 完成 | `tools/package_release.py` → `releases/PopoHere-v0.1.0.zip`（464KB） |
| 分享链接 | ✅ 已发布 | 见下方「发布提示」 |
| 多帧动画 / 换素材 | ⬜ 未做 | 见下方「已知短板」 |

## 技术选型：为什么不是 PySide6

PRD 原本定的是 **Python 3.11 + PySide6**，但 pip 安装 PySide6 被环境的安全策略（bulk-install guard）拦截，**装不上**（清华镜像也失败）。

因此改用更轻量的方案，且已经跑通：

> **原生 AppKit 外壳（Objective-C）+ WKWebView 承载 Web 版猫**

- 二进制 ~80KB × 2 架构，启动 <0.5s，**零第三方依赖**，不需要 Python 环境
- 猫的全部行为在 HTML/JS 里实现，改交互不用重新编译 → 只需 `python3 tools/build_prototype.py --native`
- 透明浮窗 + 菜单栏模板图标 + 位置/大小持久化，都是原生能力

> **2026-10-28 决定：已把 `src/ main.py requirements.txt` 那套 Python/PySide6 实现全部删除。**
> 它永远跑不起来（依赖装不上），留着只会制造"到底改哪一份"的困惑。现在**只有一套实现**：
> JS 状态机 + Objective-C 外壳。

## 拖拽为什么会抖（关键架构决策，别改回去）

早期实现里，JS 每次 mousemove 用 `e.clientX` 算出位移，再 `postMessage` 通知原生外壳移动窗口。
这有两个致命问题：

1. **坐标反馈环**：`clientX` 是相对**网页视口**的坐标，而移动的是**装着这个视口的窗口**。
   鼠标右移 10px → 窗口右移 10px → 鼠标相对视口又退回 10px → `dx` 归零 → 窗口被拉回 → 无限来回。
   用户看到的就是"剧烈抖动 + 发飘"。
2. **每帧跨进程 IPC**：WKWebView 是独立进程，`postMessage` 一来一回就是肉眼可见的延迟。

**现在的做法**：

- **移动全部由原生层负责**：外壳安装 `NSEvent` 本地监视器（`addLocalMonitorForEventsMatchingMask`），
  用**屏幕坐标**（`NSEvent mouseLocation`）在事件到达的同一时刻同步 `setFrameOrigin`，
  和 AppKit 拖窗口用的是同一套机制，零 IPC、零延迟。
- **JS 层判定改用 `e.screenX / e.screenY`**（不受窗口自身移动影响），负责推进状态机，
  不再负责移动。原生模式下一帧都不发。
  这一步是**必需的**：只把移动挪到原生是不够的，若 JS 仍用 `clientX` 判阈值，
  位移会永远卡在 0 附近 → 状态机进不了 `dragging`，松手还会被误判成"摸头"。
- **`dragging` 状态的 `motion` 从 `float` 改成 `none`**。那个 ±8px 原地漂浮动画让猫看起来一直飘着，跟"指哪打哪"直接冲突。

回归测试：`python3 tests/drag_tracking_test.py`（7 条断言），专门模拟"clientX 不动、screenX 递增"这条必死路径。

## 常用命令

```bash
# 1. 重新抠图（素材有更新时）
python3 tools/cutout.py

# 2. 重新生成页面（改了 prototype/src/ 里的 JS/模板后）
python3 tools/build_prototype.py              # → prototype/index.html（预览，带调试面板）
python3 tools/build_prototype.py --native     # → build/app/index.html（给 .app 用）

# 3. 测试（改了状态机或拖拽务必跑）
node tests/state_machine_test.js              # 32 条
python3 tests/drag_tracking_test.py           # 7 条，需要本机有 Google Chrome

# 4. 重新生成应用图标（换 icon 素材时）
python3 tools/make_icon.py                    # 默认用 themes/popo/landed.png

# 5. 重新编译桌宠（产出 dist/PopoHere.app，通用二进制 + ad-hoc 重签名）
./native/build.sh
./native/build.sh --run                       # 构建完直接启动

# 6. 打包发布
python3 tools/package_release.py              # → releases/PopoHere-v<版本>.zip

# 7. 启动
open dist/PopoHere.app        # 或双击根目录下的「启动 PopoHere.command」
```

## 目录地图

```
prototype/src/       HTML/JS 源码（template.html + app.js）
  → build_prototype.py 把源码 + 素材内联成单文件 index.html（图片转 base64 webp，10 张 ~420KB）
native/              AppKit 外壳
  PHMain.m             窗口 / WKWebView / 菜单栏 / JS 桥接 / 拖拽 / NSUserDefaults
  Info.plist           LSUIElement=1 → 不占 Dock；CFBundleIconFile=AppIcon
  build.sh             编译 x86_64+arm64 → lipo 合并 → 组装 → codesign --force --deep --sign -
themes/popo/         主题：theme.json + 10 张透明 PNG（唯一素材契约）
assets/              tray_icon.png（菜单栏模板图标）、AppIcon.icns（应用图标）
tools/               cutout.py / build_prototype.py / make_icon.py / package_release.py
tests/               state_machine_test.js、drag_tracking_test.py
dist/PopoHere.app    构建产物（768KB）
releases/            发布 zip
site/                分享落地页（index.html + cat.png + zip），已发布
使用说明.md           给最终用户的中文说明
启动 PopoHere.command 一键启动器
```

## theme.json 契约要点

- `states.<name>.visuals`：数组，进入状态时**等概率随机抽 1 张并锁定**，离开再进才重抽
- `loop` + `fps` 驱动循环；`duration`（秒）决定非循环状态停留时长
- `motion`：**本项目新增字段**（PRD 里没有），可选 `none / breathe / breathe-slow / bob-walk / shake / float / drop`
  - 注意 `dragging` 必须是 `none`，理由见上文
- `bubble`：可选 **emoji 字符串**（PRD 原本设想气泡 PNG，这里改用 emoji，少一堆素材）
- `hitBoxes`：相对坐标，**原点在图片左上角**（注意：PRD 示例用的是左下原点，与其不同，有意为之）
- 完全没有 voice/audio 字段 —— 第一版彻底无声

## 状态机关键规则（改逻辑前务必确认）

1. `startled` **只能**从 `sleep` 被点击/拖拽时进入，这是唯一入口
2. 睡中被拖 → 先 `startled`，播完如果手还按着则转入 `dragging`
3. `dragging` 是跨状态模态行为，释放后一律进 `landed`（有素材）或 `idle`，**不回到原状态**
4. `walk` 被点击一律回 `idle`（打断），不走摸头/摸脚
5. `menu` 状态下所有左键事件忽略；状态机自带 2 秒兜底回 `idle`
6. 单击判定：位移 <5px **且** 耗时 <300ms
7. `scratch` 结束后 3 秒冷却，冷却期内摸脚只出 `pet_paw`
8. **踩过的坑**：连续摸脚判定必须在「摸脚那一刻」计算与上一次的间隔，不能在 `pet_paw` 结束时算（那样第一次摸脚就会自触发 scratch）

## 打包与分发

`tools/package_release.py` 产出的 zip，顶层是一个文件夹，里面只有三样东西：

```
PopoHere-v0.1.0/
├── PopoHere.app
├── 启动 PopoHere.command     清掉 quarantine 标记后启动，给不会右键打开的人
└── 使用说明.md
```

刻意**不含**：`素材/`、`归档/`、tools/tests/prototype 等工程文件 —— 给普通朋友的就是"双击能用"三件套。

- 压缩用 `ditto -c -k --keepParent`，不要用 `--sequesterRsrc`（会多出一个 `__MACOSX` 目录）
- app 是 ad-hoc 签名（`codesign --force --deep --sign -`），**没有 Apple 公证** →
  别人电脑上第一次要右键→打开。`build.sh` 末尾会自动校验签名（`valid on disk`）
- 已验证：从上线的链接下载 zip → 解压 → 双击 app 可正常启动

## 发布提示

落地页在 `site/`，已通过 App 发布能力上线，地址为
`https://popohere-download.app.workbuddy.host/?sharecode=FJMG36UVIX`
（后台在「设置—数据管理—应用」里管理）。

**这里的坑：静态资源直接访问会被网关拦 403，必须带上 `sharecode` 查询参数。**
页面里的下载链接是相对路径，所以 `site/index.html` 底部有一段脚本，运行时把 `location.search`
拼到 href 上；`location.search` 为空时回退到带 sharecode 的绝对地址。
**改这个页面后如果要换 URL，记得同步改那段脚本里的回退地址。**

## 已知短板 / 下一步建议

1. **素材重复**：源文件里 `pet_head/pet_paw/scratch` 是同一个文件，`walk/landed` 也是同一个文件（md5 验过）。所以现在摸头/摸脚/挠人长得一样。→ 需要用户补图：**不同摆拍动作的多张**，尤其是 `walk`（建议 2–4 帧走路姿态）、`pet_head`（眯眼/享受）、`scratch`（抬爪）
2. **每状态只有 1 帧**：`idle`/`sleep` 建议各 3–5 张，用来验证随机抽图和多帧呼吸感
3. **hitbox 是全局的**：`sleep`/`idle` 是躺姿，现在全落在下半区。可以考虑改成按状态配 hitbox（theme.json 里支持 per-state 覆盖）
4. **原生版素材写死在 HTML 里（base64）**：用户不能直接换图。→ 后续可改成从 app 包内的真实文件路径加载，恢复 PRD 的「替换素材」能力
5. **没有登录自启动**：可加 `~/Library/LaunchAgents/com.popohere.pet.plist`
6. **拖拽对 Cursor 精度的最后一点**：现在 `NSEvent` 本地监视器不吞事件（返回原 event），JS 才能收到 mouseup 推进状态机。极快速的甩手操作理论上可能出现"猫动了但状态还没进 dragging"，概率极低，真遇到再处理

## 环境踩坑记录

- Swift 工具链**不可用**：只装了 Command Line Tools，`swiftc` 报 `redefinition of module 'SwiftBridging'` → 别走 Swift 路线
- **clang + Objective-C 完全可用**（`-fobjc-arc -framework Cocoa -framework WebKit`）；`-arch arm64 -arch x86_64` 分别编译再 `lipo -create` 可出通用二进制
- `pip install` 大依赖树会被安全策略拦截；rembg/PIL/numpy 已装好可用
- `screencapture` 因缺屏幕录制权限无法写盘；`log show` 也读不到本进程日志 → **验证 GUI 只能靠 `pgrep` + `defaults read com.popohere.pet`**
- **合成鼠标事件（CGEventPost）注入不进来**：本机没授予任何进程辅助功能权限（`AXIsProcessTrusted` = NO），事件会被系统丢弃。所以"拖拽是否跟手"这类手感问题**没法自动验证，只能让用户手测**
- 用 shell 创建/改动 `.app` 目录偶发被沙箱拦；用 Python 的 `os.makedirs`/`shutil` 组装可绕过
- **macOS 自带 grep 是 BSD 版，BRE 不支持 `\|`**！`grep "a\|b"` 会被当成字面字符串、静默无匹配。要用 `-E` 或多个 `-e`
- headless Chrome 里页面被视为后台标签，`setInterval`/`requestAnimationFrame` 会被节流 → 写自动化测试时别读 DOM 上的状态文字（会永远是陈旧的），直接调用 `window.App.state()`
- 已验证：headless Chrome 可截图验 HTML 原型、可用 `--dump-dom` 跑页面内断言
  （`"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir=... --dump-dom ...`）
