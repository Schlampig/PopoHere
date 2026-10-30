# 架构说明

给要改这个项目的开发者看。产品层面请看 [PRD](PRD/PRD.md)，AI 接手请看 [AGENTS.md](../AGENTS.md)。

## 一句话架构

> 一个 Objective-C 的透明浮窗，里面塞一个 WebView；猫的所有行为都是网页里的 JS 在跑。

```
┌─────────────────────────────────────────────┐
│  PopoHere.app                               │
│  ┌───────────────────────────────────────┐  │
│  │ func_window  (Objective-C)            │  │
│  │  · 无边框透明 NSWindow，置顶、不进 Dock  │  │
│  │  · 菜单栏 NSStatusItem                 │  │
│  │  · 拖拽：NSEvent 本地监视器 → 屏幕坐标    │  │
│  │  · 位置/大小/视图 → NSUserDefaults      │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │ WKWebView                       │  │  │
│  │  │  func_state   状态机（纯逻辑）    │  │  │
│  │  │  func_render  状态 → 贴图/动效    │  │  │
│  │  │  func_input   命中判定/单击拖拽    │  │  │
│  │  │  func_menu    右键菜单            │  │  │
│  │  │  main         装配 + 主循环       │  │  │
│  │  └─────────────────────────────────┘  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

为什么不用 Swift / PySide6：见 [AGENTS.md](../AGENTS.md) 的「技术选型」。简单说，这台机器只有 Command Line Tools，Swift 工具链不可用，而 PySide6 装不上；`clang + Objective-C + WebKit` 是当场唯一能编译、零依赖、体积最小的方案。

把交互逻辑留在 JS 里的额外好处：改行为不用重新编译，`build_web.py` 十毫秒跑完，浏览器里直接能看到效果。

## 各模块职责

| 模块 | 位置 | 职责 | 不该做的事 |
|---|---|---|---|
| `func_state` | `core/func_state/` | 状态流转、按概率选视觉、单击/拖拽对状态的语义 | 碰 DOM、读全局变量 |
| `func_render` | `core/func_render/` | 状态 → 贴图 src / 动效 class / 气泡 | 改状态、算鼠标 |
| `func_input` | `core/func_input/` | 命中区域、单击 vs 拖拽、预览模式下的 DOM 位移 | 决定进入哪个状态 |
| `func_menu` | `core/func_menu/` | 右键菜单的打开/关闭/菜单项行为 | 管窗口 |
| `main` | `core/main.js` | 装配、主循环、尺寸与位置、`window.App` 对外 API | 塞业务逻辑 |
| `func_window` | `core/func_window/` | 窗口、菜单栏、拖拽跟踪、持久化、JS 桥 | 管猫的状态 |

状态机不 import 任何 DOM API，所以能被 Node 直接跑测试（`code/test/state_machine_test.js`）。这条边界**不要打破**——它是唯一一个能脱离 GUI 做回归测试的地方。

## 数据流

```
theme.json ──┐
             ├─→ build_web.py ─→ 内联成单个 index.html ─→ WKWebView
pet_images ──┘                      (图片转 base64 webp)

用户操作 ─→ func_input ─→ PetStateMachine ─→ func_render ─→ DOM
                │                 ↑
                └── 原生模式 ──→ func_window（屏幕坐标移动窗口）
```

## 拖拽：一个必须记住的坑

**症状**：拖动时画面剧烈抖动，光标和猫之间有延迟，像拖一根橡皮筋。

**根因**：早期版本 JS 每次 `mousemove` 都用 `e.clientX` 算位移，然后 `postMessage` 让原生窗口跟着动。

`clientX` 是**相对网页视口**的坐标，而移动的正是**装着这个视口的窗口**。于是：

```
鼠标右移 10px → 窗口右移 10px → 鼠标相对视口退回 10px → dx 归零 → 窗口被拉回 → 又右移…
```

这就是一个坐标系自我抵消的负反馈环。叠加 WKWebView 跨进程 `postMessage` 的延迟，表现就是又抖又飘。

**现行做法**：

1. **窗口位移全部由原生层做**。`func_window` 在收到 `press` 后装一个 `NSEvent` 本地监视器，用 `[NSEvent mouseLocation]`（屏幕坐标）在事件到场的**同一瞬间** `setFrameOrigin`。和 AppKit 拖标题栏是同一套机制，零 IPC。位移按「按下时的绝对原点 + 累计屏幕位移」算，不累积误差。
2. **JS 判定也改用 `e.screenX / e.screenY`**。这一步是必需的：移动交给原生后，如果 JS 还用 `clientX` 判阈值，位移会永远卡在 0 附近，状态机永远进不了 `dragging`，松手还会被误判成"摸头"。
3. **原生模式下 JS 一帧都不发位移消息**，只发 `press` / `release` 两个事件。

**回归测试**：`code/test/drag_tracking_test.py` 专门构造"`clientX` 纹丝不动、只有 `screenX` 递增"的场景（也就是窗口跟随后视口的真实表现）。这条用例在旧实现上必挂——改拖拽相关代码前先跑它。

另一个容易被忽略的点：`theme.json` 里 `dragging` 状态的 `motion` 必须是 `none`。早期用 `float`（±8px 上下漂浮 + ±3° 旋转）会让猫在手里一直晃，和"指哪打哪"直接冲突。

## theme.json：状态与贴图的契约

```jsonc
{
  "behavior": {              // 全局行为参数
    "idle_duration_sec": 5,  // 静息多久后开始自己找事做
    "walk_probability": 0.3, // 静息结束后去溜达的概率（其余去睡觉）
    "scratch_probability": 0.3,
    "scratch_cooldown_sec": 3,
    "repeat_paw_window_sec": 3,
    "click_max_drift_px": 5,     // 位移小于它 = 单击
    "click_max_duration_ms": 300, // 时长小于它 = 单击
    "menu_timeout_sec": 2,
    "polling_interval_ms": 50
  },
  "states": {
    "idle": {
      "visuals": ["idle.png", "idle_2.png"],  // 进入状态时等概率抽一张并锁定
      "loop": true,
      "duration": 1.5,      // 非循环状态的停留秒数；循环状态可省略
      "motion": "breathe",  // none / breathe / breathe-slow / bob-walk / shake / float / drop
      "bubble": "💤"        // 可选，emoji 气泡
    }
  },
  "hitBoxes": {
    "head": { "x": 0.26, "y": 0.02, "w": 0.48, "h": 0.46 },  // 相对比例，原点在左上角
    "paw":  { "x": 0.08, "y": 0.52, "w": 0.84, "h": 0.48 }
  }
}
```

`motion` 是 PRD 里没有、本项目新增的字段：用 CSS 动画给静态图一点生命感，省掉逐帧素材。
`bubble` 用 emoji 而不是图片，也是为了少一堆素材。

## 构建管线

```
source/origin_images/*.png
        │  code/prepare/cutout.py        (rembg 去背景 + 归一化，约 1s/张)
        ▼
code/pet_images/*.png  +  theme.json    (手工维护/生成的契约)
        │  code/build/build_web.py       (内联 JS 模块 + 贴图转 base64 webp)
        ▼
code/build/out/native.html              (单文件，约 420KB)
        │  code/build/build_app.sh       (clang 双架构 → lipo → 组装 → ad-hoc 签名)
        ▼
code/build/dist/PopoHere.app            (768KB)
        │  code/build/package_release.py (ditto 压缩 + 生成启动脚本)
        ▼
code/build/releases/PopoHere-v1.0.0.zip (约 464KB)
```

贴图在 `build_web.py` 里就被 base64 内联了，所以 `.app` 包内不再放一份 `pet_images` 副本——早期的版本犯过这个错，白胖 3.7MB。

## 签名与分发

- 构建末尾执行 `codesign --force --deep --sign -`（ad-hoc 签名）并校验。**必须在组装完包之后再签**，否则会出现"code has no resources but signature indicates they must be present"。
- 没有 Apple 公证，别人下载后首次打开要右键 →「打开」。这一点在 README 和使用说明里都写了。
- `ditto` 打包时**不要**加 `--sequesterRsrc`：包内没有 resource fork，加了只会多出一个 `__MACOSX` 目录。
