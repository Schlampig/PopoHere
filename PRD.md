# PRD

# PopoHere 产品需求文档 v1\.0



**项目名称**：PopoHere

**版本**：v1\.0（完整产品规格 \+ 开发环境配置指南）

**最后更新**：2026\-10\-27

**第一版目标**：在 macOS 上以 Python \+ PySide6 跑通完整的无声桌宠状态、交互与视觉反馈；分发优先尝试 `.app`，受阻则退回 GitHub 源码分发。

**开发方式**：通过 DSH / Workbuddy 以 MCP 方式调用大模型 API，在本地进行 vibe coding。





## 第一章 任务背景



### 1\.1 一句话描述



PopoHere 是一个以用户自家猫咪Popo的真实照片为素材、**纯本地运行、零外部 API 依赖、完全无声**的桌面宠物。第一版在 macOS 上运行，技术栈为 **Python 3\.11\+ \+ PySide6**。所有素材与逻辑通过 `theme.json` 契约解耦，便于他人替换素材生成自己的桌宠。



### 1\.2 核心约束



|约束|决定|
|---|---|
|运行环境|**第一版仅 macOS**；Windows 适配推迟|
|外部依赖|**零 API 调用**；仅使用系统框架与 PySide6|
|**音频**|**完全无声**。不加载、不播放任何音频文件；代码中不引用任何音频库|
|图片素材|每个**必需状态**至少 1 张；`sleep` 建议多张以验证随机|
|气泡素材|**可选**；缺失时静默跳过，不阻断状态执行|
|全局鼠标监听|**不做**；不请求辅助功能权限；`sleep` 计时仅基于窗口内鼠标操作|
|素材解耦|功能代码中不出现任何文件名；`theme.json` 是唯一映射契约|
|小游戏|**预留空位**；点击空白区**不作任何响应**，仅保留代码钩子|



### 1\.3 视觉风格约束



素材基于真实猫咪照片的艺术化处理（像素风 / 油画风），通常是静态单帧或少量帧。因此：不做视线追踪；不做需要逐帧骨骼绑定的复杂动画；`walk` 第一版只做原地走动视觉，不改变窗口坐标。





## 第二章 状态定义



### 2\.1 状态总表（共 9 个必需状态 \+ 1 个可选状态）



|状态 ID|中文名|必需|视觉素材|气泡/表情（可选）|进入条件|退出路径|
|---|---|---|---|---|---|---|
|`idle`|待机|是|≥1 张，循环|无|启动默认；短时状态回归点|5 秒后 30%→`walk` / 70%→`sleep`；点击头部→`pet_head`；点击脚部→`pet_paw`；拖拽→`dragging`；右键→`menu`|
|`walk`|走动|是|≥1 张/组，原地|无|`idle` 持续 5 秒后 30% 概率选中|播放 2–3 秒→`idle`（重新开始 5 秒计时）；点击→`idle`（打断）|
|`sleep`|睡觉|是|**≥1 张，建议 3–5 张随机**|`💤`|`idle` 持续 5 秒后 70% 概率选中|点击/拖拽→`startled`|
|`pet_head`|摸头|是|1 张|`❤️` / `😌`|左键单击头部 hitbox|播放 1\.5 秒→`idle`|
|`pet_paw`|摸脚|是|1 张|`❗` / `😾`|左键单击脚部 hitbox|30% 概率→`scratch`；否则→`idle`|
|`scratch`|挠人|是|1 张|`💢`|`pet_paw` 概率触发，或 3 秒内连续摸脚|播放 1\.5 秒→`idle` \+ 3 秒冷却|
|`startled`|受惊|是|1 张|`❗` / `😲`|**仅当 ****`sleep`**** 状态下**点击或拖拽唤醒|播放 1\.0 秒→`idle`|
|`dragging`|拖拽中|是|**独立专用图**（被抱起/悬空）|无|任意状态（除 `menu`）左键按住并位移 \>5px|释放→`landed`（若有素材）或直接→`idle`|
|`landed`|落地|**可选**|1 张（被放下姿态）|无|`dragging` 释放后，若 `theme.json` 定义了该状态|播放 0\.8 秒→`idle`|
|`menu`|菜单等待|是|1 张（端正坐好/注视）|无|右键窗口任意位置|菜单项触发→对应行为；2 秒兜底超时→`idle`|



### 2\.2 状态转换矩阵（覆盖所有潜在衔接）



以下矩阵以“当前状态 × 事件”列出目标状态。**空单元格表示忽略**，不产生状态变化。



|当前状态 ↓ \\ 事件 →|单击头部|单击脚部|单击空白|左键拖拽 \>5px|右键|窗口内 5s 无操作|walk 播放完毕|短时状态播放完毕|拖拽释放|
|---|---|---|---|---|---|---|---|---|---|
|`idle`|`pet_head`|`pet_paw`|**忽略**（小游戏钩子）|`dragging`|`menu`|30% `walk` / 70% `sleep`|—|—|—|
|`walk`|`idle`|`idle`|`idle`|`dragging`|`menu`|—|`idle`|—|—|
|`sleep`|`startled`|`startled`|`startled`|`startled`→`dragging`|`menu`|—|—|—|—|
|`pet_head`|忽略|忽略|忽略|`dragging`|`menu`|—|—|`idle`|—|
|`pet_paw`|忽略|忽略|忽略|`dragging`|`menu`|—|—|`scratch` 或 `idle`|—|
|`scratch`|忽略|忽略|忽略|`dragging`|`menu`|—|—|`idle`|—|
|`startled`|忽略|忽略|忽略|`dragging`|`menu`|—|—|`idle`|—|
|`dragging`|—|—|—|—|忽略|—|—|—|`landed` 或 `idle`|
|`landed`|忽略|忽略|忽略|`dragging`|`menu`|—|—|`idle`|—|
|`menu`|忽略|忽略|忽略|忽略|—|2s 兜底→`idle`|—|—|—|



**关键衔接规则**：



- **`sleep`**** 被点击/拖拽时统一先进入 ****`startled`**，而不是直接进入 `pet_head` / `pet_paw`。这避免了“猫在睡觉时被摸头却给出摸头反应”的逻辑断裂。`startled` 播放完毕后回 `idle`，用户可以在猫醒来后再次摸头。

- **`startled`**** 触发条件严格收窄**：仅在 `sleep` 状态下发生点击或拖拽时进入。`idle`、`walk` 等其他状态的点击/拖拽**不触发** `startled`。

- **`dragging`**** 是跨状态的模态行为**（除 `menu` 外均可进入）。释放后一律不回到原状态，而是进入 `landed`（若有素材）或直接回 `idle`。不做“从 sleep 拖拽后回 sleep”的记忆。

- **`walk`**** 被点击时一律回 ****`idle`**，不触发摸头/摸脚。走动中的猫不适合精确命中 hitbox，且符合“打断”直觉。

- **`menu`**** 状态下所有鼠标左键事件被忽略**，直到菜单关闭，防止误触导致状态混乱。

    

### 2\.3 随机与冷却规则



- **状态内随机锁定**：进入任何状态时，从该状态的 `visuals` 数组中**等概率随机选 1 项并锁定**，状态持续期间不变。离开后重新进入才重新抽取。这是“Sleep 有 5 张图随机选 1”的实现方式。

- **`idle`**** 5 秒后的分流**：`idle` 持续满 `idle_duration_sec`（默认 5 秒）时，按 `behavior.walk_probability`（**默认 0\.30**）随机决定进入 `walk` 或 `sleep`。若进入 `walk`，播放完毕回 `idle` 并**重新开始** 5 秒计时；若进入 `sleep`，持续到被唤醒。

- **`pet_paw`**** → ****`scratch`**** 概率**：默认 **0\.30**，可在 `behavior.scratch_probability` 配置。

- **`scratch`**** 冷却**：`scratch` 结束后 **3 秒**内，再次摸脚不会触发 `scratch`，只会执行 `pet_paw`。

- **`walk`**** 播放时长**：由 `theme.json` 中该状态的 `duration` 字段决定，建议 2–3 秒。

    

### 2\.4 交互判定规则



- **左键单击**：`mousePressEvent` 记录时间戳与坐标；`mouseReleaseEvent` 时，若**位移 \<5px 且耗时 \<300ms**，判定为单击。命中头部→`pet_head`；命中脚部→`pet_paw`；命中空白→**无任何响应**（不弹窗、不切换状态，仅内部钩子）。

- **左键拖拽**：`mouseMoveEvent` 中若按住左键且**位移 ≥5px**，进入 `dragging`，窗口跟随鼠标移动。拖拽期间不响应单击事件。

- **右键**：窗口**任意位置**右键，进入 `menu` 并弹出功能菜单。触控板用户通过系统“辅助点按”（双指轻点 / Control\+单击 / 角落点按）触发，**应用侧无需特殊处理**。

- **`sleep`**** 计时**：在 `PetWindow` 中维护一个 `QTimer`，仅在窗口内发生鼠标**按下/拖拽**时重置。鼠标在窗口外移动**不重置**计时。不请求辅助功能权限。

    

### 2\.5 Hitbox 定义



Hitbox 在 `theme.json` 中使用**相对坐标**（0–1 小数），与素材实际像素尺寸解耦：



```JSON
"hitBoxes": {
  "head": { "x": 0.25, "y": 0.55, "w": 0.50, "h": 0.35 },
  "paw":  { "x": 0.10, "y": 0.00, "w": 0.80, "h": 0.25 }
}
```



头部与脚部区域**不重叠**；两个 hitbox 之外的区域视为“空白区”。如果用户素材构图不同，只需修改这两个矩形。





## 第三章 技术架构与技术栈



### 3\.1 技术栈决定



|项目|决定|理由|
|---|---|---|
|语言|**Python 3\.11 或 3\.12**|你更熟悉；PySide6 官方推荐范围|
|UI 框架|**PySide6**|成熟的无边框/透明/置顶窗口支持|
|动画|**`QTimer`**** 驱动 ****`QPixmap`**** 帧切换**|素材以静态单帧为主，帧切换已足够|
|音频|**无**|完全无声版本，不引入任何音频库|
|气泡|**子 ****`QLabel`**** / 独立子 ****`QWidget`**，绝对定位在宠物图右上角|透明背景，不参与 hitbox 判定|
|状态机|**纯 Python 类**，**不 import PySide6**|可单元测试；未来迁移 Swift 时逻辑可原样移植|
|配置|`theme.json` \+ `config.json`|`theme.json` 素材契约；`config.json` 用户偏好（窗口位置、暂停互动开关）|
|打包|**优先 ****`pyside6-deploy`**；受阻则 PyInstaller|Qt 官方工具，基于 Nuitka，macOS 生成 `.app`|



**关于 ****`pyside6-deploy`**** 的实测信息**：它是 Qt 官方从 6\.4 起提供的部署工具，底层封装 Nuitka（将 Python 编译为 C 再打包）。在 macOS 上**始终生成 ****`.app`**** 应用程序包**；默认打包模式从 6\.12 起为 **standalone**（一个包含可执行文件及全部依赖的文件夹），而非 onefile。作为参考，中等复杂度 PySide6 应用使用 PyInstaller 打包后约 **85MB、启动 2\.3 秒**，Nuitka（即 `pyside6-deploy` 底层）约 **52MB、启动 0\.8 秒**。对于 PopoHere 这个量级的桌宠，两者均可接受，但 `pyside6-deploy` 是官方推荐路径。



### 3\.2 分层架构



```Plain Text
┌─────────────────────────────────────────────┐
│  ① 状态机层 (PetStateMachine)                │
│  纯 Python，无 PySide6 导入                   │
│  输入：抽象事件（on_click_head, on_timeout…） │
│  输出：状态字符串（"idle", "sleep", "menu"…） │
└──────────────────┬──────────────────────────┘
                   │ 状态名
                   ▼
┌─────────────────────────────────────────────┐
│  ② 主题层 (ThemeLoader)                      │
│  读取 theme.json，状态名 → 素材路径 + 参数    │
│  素材缺失时回退到内置默认主题                 │
└──────────────────┬──────────────────────────┘
                   │ QPixmap / 气泡路径
                   ▼
┌─────────────────────────────────────────────┐
│  ③ 渲染与交互层 (PetWindow, TrayController)   │
│  PySide6 透明无边框置顶 QWidget               │
│  鼠标事件翻译 → 抽象事件 → 喂给状态机          │
│  菜单栏 QSystemTrayIcon                       │
└─────────────────────────────────────────────┘
```



**关键工程规则**：`PetStateMachine` **不 import PySide6**。它只接受纯 Python 事件对象，输出纯 Python 字符串。`PetWindow` 负责把 `QMouseEvent` 翻译成 `on_click_head()`、`on_drag_start()` 等抽象方法。



### 3\.3 macOS 第一版的关键实现要点



**透明无边框置顶窗口**：Qt 官方文档明确说明，在 macOS 上要让透明背景生效，**`Qt.FramelessWindowHint`**** 是必要条件**，需与 `Qt.WA_TranslucentBackground` 配合使用。推荐组合：



```Python
self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
self.setWindowFlags(
    Qt.WindowType.FramelessWindowHint
    | Qt.WindowType.WindowStaysOnTopHint
    | Qt.WindowType.Tool          # 不占 Dock / 不抢焦点
)
```



第一版**不做点击穿透**——右键菜单需要在整个窗口任意位置可用，保持整个窗口接收鼠标事件反而简化实现。



**单击 vs 拖拽判定**：在 `mousePressEvent` 记录时间戳与坐标；`mouseMoveEvent` 中位移 ≥5px 则标记为拖拽；`mouseReleaseEvent` 中若未进入拖拽且耗时 \<300ms，判定为单击。300ms 的阈值是桌宠场景的合理值；如果实际体验中觉得单击过于敏感或迟钝，可在 `config.json` 中暴露为可调参数。



**菜单栏与 ****`menu`**** 状态的双重保障**：`QSystemTrayIcon` 在 macOS 上可用，但历史上 `QMenu.aboutToHide` 信号在 macOS 上存在不可靠的记录（曾被转换为 `NSMenu` 而不发射该信号）。尽管 Qt 在 2022 年的提交中声称该问题“如今工作正常”，但**为了跨 Qt 版本的稳健性**，v1\.0 仍采用双重保障：



1. **每个 ****`QAction`**** 的 ****`triggered`**** 信号中显式调用 ****`state_machine.on_menu_closed()`**；

2. 右键菜单弹出后启动一个 **2 秒单次 ****`QTimer`**，超时无选择则强制 `on_menu_closed()`，防止用户点击菜单外部但未选择任何项时猫永远停留在 `menu`。

    

**气泡渲染**：在 `PetWindow` 中增加一个**绝对定位的子 ****`QLabel`**（或子 `QWidget` \+ `QLabel`），背景透明，显示在宠物图右上角偏移位置。气泡**不参与 hitbox 判定**，鼠标事件穿透到父窗口。切换状态时根据 `theme.json` 中该状态的 `bubble` 字段加载并显示/隐藏；字段缺失或文件不存在时静默跳过。



### 3\.4 目录结构



```Plain Text
PopoHere/
├── main.py                     # 入口：QApplication + 装配
├── requirements.txt            # PySide6
├── pyproject.toml              # 可选
├── src/
│   ├── core/
│   │   ├── pet_state.py        # 状态枚举（纯 Python）
│   │   ├── state_machine.py    # 纯 Python 状态机
│   │   └── theme.py            # theme.json 的 dataclass 模型
│   ├── ui/
│   │   ├── pet_window.py       # 透明无边框 QWidget
│   │   ├── animation.py        # QTimer 帧切换
│   │   ├── bubble.py           # 气泡子 QLabel 封装
│   │   └── tray.py             # QSystemTrayIcon + QMenu
│   └── interaction/
│       └── mouse.py            # 单击/拖拽判定 + hitbox 命中
├── themes/
│   └── default/                # 内置默认主题（占位素材）
│       ├── theme.json
│       ├── idle_1.png
│       ├── sleep_1.png
│       └── ...
├── assets/
│   └── tray_icon.png           # 菜单栏图标
├── docs/
│   └── PRD.md
└── README.md
```



**注意**：

- v1\.0 目录中**没有 ****`src/audio/`**，`requirements.txt` 中**没有音频相关依赖**。

- 以上目录没有包含两个文件夹“素材”与“归档”，这两个文件夹内的内容可以访问、阅读、取用，但不可改动！！！其中“素材”文件夹装有现有桌宠状态的图片，图片名称即状态，同一个状态多个图片靠序号来区分。





## 第四章 分步准备指南（你需要手动完成的操作）



### 第一步：安装 Python 与开发工具



|工具|版本|安装方式|
|---|---|---|
|**Python**|**3\.11 或 3\.12**|从 [python\.org](https://www.python.org/downloads/macos/) 下载 macOS 安装包。安装后在终端执行 `python3 --version` 确认|
|**VS Code**（推荐）|最新|从 [code\.visualstudio\.com](https://code.visualstudio.com/) 下载；安装 **Python 扩展**（Microsoft 官方）|
|**Xcode Command Line Tools**|—|终端执行 `xcode-select --install`（某些 PySide6 依赖或打包步骤可能需要）|



**不需要 Xcode 完整版**。PySide6 是跨平台框架，macOS 上不需要 Xcode 即可运行和打包。



### 第二步：建立项目目录与虚拟环境



在终端中执行：



```Bash
# 1. 创建项目根目录（位置可自选，这里以 ~/Developer 为例）
mkdir -p ~/Developer/PopoHere
cd ~/Developer/PopoHere

# 2. 创建子目录
mkdir -p src/{core,ui,interaction}
mkdir -p themes/default
mkdir -p assets
mkdir -p docs

# 3. 创建 Python 虚拟环境
python3 -m venv venv

# 4. 激活虚拟环境
source venv/bin/activate

# 5. 安装 PySide6
pip install PySide6

# 6. 确认安装
python -c "import PySide6; print(PySide6.__version__)"
```



Qt 官方**强烈建议**使用 `venv` 虚拟环境，并避免在系统 Python 中直接 `pip install PySide6`。每次打开新终端窗口进行开发前，都需要先执行 `source venv/bin/activate`。



### 第三步：创建 `requirements.txt`



在项目根目录创建 `requirements.txt`，内容为：



```Plain Text
PySide6>=6.6,<7
```



之后其他用户克隆你的仓库后，只需执行 `pip install -r requirements.txt` 即可复现环境。



### 第四步：准备最小素材集



**不要等 20 张素材齐全再开始。** 第一版跑通状态机只需要以下素材：



|状态|最少素材|建议格式|备注|
|---|---|---|---|
|`idle`|1 张|PNG，透明背景，512×512|循环待机|
|`walk`|1–2 张|PNG，同上|原地走动视觉|
|`sleep`|**2–3 张**|PNG，同上|用于验证随机选图|
|`pet_head`|1 张|PNG|摸头反应|
|`pet_paw`|1 张|PNG|摸脚反应|
|`scratch`|1 张|PNG|挠人反应|
|`startled`|1 张|PNG|睡中受惊|
|`dragging`|**1 张独立专用图**|PNG|被抱起/悬空姿态，**不可复用 idle**|
|`landed`|**可选**|PNG|落地姿态；没有则跳过|
|`menu`|1 张|PNG|端正坐好/注视|
|**气泡**|**全部可选**|PNG，小尺寸（如 64×64）|`bubble_zzz.png`、`bubble_heart.png` 等；缺失时不显示|



将素材放入 `themes/default/`，文件名使用 `状态名_序号.png` 的约定（如 `sleep_1.png`、`sleep_2.png`）。同时在 `themes/default/theme.json` 中声明素材映射（结构见 5\.1 节）。



### 第五步：配置 DSH / Workbuddy 进行 AI 辅助开发



你计划通过 DSH 或 Workbuddy 调用 API 来 vibe coding。这两个工具的核心能力是**让 AI 读写本地文件、执行命令**，从而在项目目录中直接生成和调试代码。



**建议的工作流**：



1. **将本 PRD 保存为 ****`docs/PRD.md`**，作为 AI 的“唯一真相来源”。每次开启新会话或新任务时，让 AI 先读这份文档。

2. **按模块拆分任务，一次只让 AI 做一件事**。推荐顺序：

    - 第 1 轮：`theme.py` \+ `themes/default/theme.json`（素材契约）

    - 第 2 轮：`state_machine.py`（纯逻辑，可先用 `print` 验证状态转换）

    - 第 3 轮：`pet_window.py` \+ `animation.py`（窗口显示 `idle` 帧）

    - 第 4 轮：`mouse.py`（单击/拖拽/hitbox 判定）

    - 第 5 轮：`bubble.py`（气泡显示）

    - 第 6 轮：`tray.py`（菜单栏）

    - 第 7 轮：`main.py`（装配全部）

3. **每次 AI 生成代码后，立刻用 ****`python main.py`**** 运行验证**。不要等全部模块写完再跑。如果报错，把**完整错误信息**贴回给 AI，让它只修当前问题。

4. **利用工具的“命令执行”能力**：你可以直接让 AI 执行 `pip install ...` 或 `python main.py`，而不需要自己在终端反复切换。但首次的 `venv` 创建和激活建议你手动完成，确保环境干净可控。

5. **不要一次把整个 PRD 丢给 AI 让它“生成完整项目”**。桌宠的状态机和 UI 事件循环有大量时序细节，一次性生成的代码往往在交互衔接处出错。**分模块、逐步验证**是 vibe coding 在这个项目上最有效的节奏。

    

### 第六步：打包与分发



**路径 A（优先）** ：`pyside6-deploy`。



```Bash
# 在虚拟环境中
pip install pyside6-deploy
pyside6-deploy main.py
```



macOS 上会生成 `PopoHere.app`（位于 `main.dist/` 或当前目录下的 `.app`）。首次运行会在项目目录创建 `pysidedeploy.spec`，后续可调整打包参数。



**路径 B（路径 A 受阻时）** ：PyInstaller。



```Bash
pip install pyinstaller
pyinstaller --windowed --name PopoHere main.py
```



生成 `dist/PopoHere.app`。



**Gatekeeper 提示**：未公证的 `.app` 在别人电脑上首次打开会提示“无法验证开发者”。个人分享的常见做法是在 README 中说明“右键 → 打开”，或指导用户执行：



```Bash
xattr -dr com.apple.quarantine /path/to/PopoHere.app
```



彻底消除摩擦需要 Apple Developer Program（$99/年）并做公证。**第一版不做公证**。



**如果打包阻力过大**：退回 **GitHub 源码分发**。README 中写清：



```Bash
git clone <repo>
cd PopoHere
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python main.py
```



先让桌宠在你自己的 Mac 上跑起来，打包是最后一步，不是阻塞项。





## 第五章 `theme.json` 契约（完整示例）



```JSON
{
  "id": "popo",
  "displayName": "Popo",
  "version": "1.0",
  "behavior": {
    "idle_duration_sec": 5,
    "walk_probability": 0.30,
    "scratch_probability": 0.30,
    "scratch_cooldown_sec": 3
  },
  "states": {
    "idle": {
      "visuals": ["idle_1.png"],
      "loop": true,
      "fps": 1
    },
    "walk": {
      "visuals": ["walk_1.png", "walk_2.png"],
      "loop": true,
      "fps": 4,
      "duration": 2.5
    },
    "sleep": {
      "visuals": ["sleep_1.png", "sleep_2.png", "sleep_3.png"],
      "bubble": "bubble_zzz.png",
      "loop": true,
      "fps": 1
    },
    "pet_head": {
      "visuals": ["happy_1.png"],
      "bubble": "bubble_heart.png",
      "loop": false,
      "duration": 1.5
    },
    "pet_paw": {
      "visuals": ["paw_1.png"],
      "bubble": "bubble_exclaim.png",
      "loop": false,
      "duration": 1.0
    },
    "scratch": {
      "visuals": ["scratch_1.png"],
      "bubble": "bubble_anger.png",
      "loop": false,
      "duration": 1.5
    },
    "startled": {
      "visuals": ["startled_1.png"],
      "bubble": "bubble_surprise.png",
      "loop": false,
      "duration": 1.0
    },
    "dragging": {
      "visuals": ["dragging_1.png"],
      "loop": true,
      "fps": 1
    },
    "landed": {
      "visuals": ["landed_1.png"],
      "loop": false,
      "duration": 0.8
    },
    "menu": {
      "visuals": ["menu_1.png"],
      "loop": true,
      "fps": 1
    }
  },
  "hitBoxes": {
    "head": { "x": 0.25, "y": 0.55, "w": 0.50, "h": 0.35 },
    "paw":  { "x": 0.10, "y": 0.00, "w": 0.80, "h": 0.25 }
  }
}
```



**契约要点**：



- `visuals` 是**数组**，进入状态时等概率随机选 1 项并锁定。

- `bubble` 是**可选字符串**；缺失或文件不存在时静默跳过，不报错、不阻断。

- `landed` 整个状态是**可选**的；`theme.json` 中不定义时，`dragging` 释放后直接回 `idle`。

- `loop` \+ `fps` 驱动 `QTimer` 帧切换；`duration` 决定非循环状态的停留时长（秒）。

- **没有任何 ****`voice`**** 字段**；代码中不引用音频路径。

    

    

## 第六章 菜单栏



菜单栏**不是桌宠自己弹窗**，而是在 macOS 屏幕右上角的系统菜单栏中放置一个小图标（`QSystemTrayIcon`）。点击图标下拉原生菜单。菜单项包括：



|菜单项|行为|
|---|---|
|**显示 / 隐藏桌宠**|切换 `PetWindow` 的可见性|
|**暂停互动**|宠物继续待机/动画，但**不响应**摸头、摸脚、拖拽（防止误触）；状态持久化到 `config.json`|
|**打开主题文件夹**|在 Finder 中打开 `themes/default/`，方便替换素材|
|**退出**|退出应用|



**`menu`**** 状态的双重保障**（见 3\.3 节）：每个 `QAction` 触发后显式通知状态机；2 秒兜底定时器强制恢复，防止 macOS 上菜单关闭信号不可靠导致卡死。



**不再包含“语音开关”**。





## 第七章 明确不做的（v1\.0）



|不做项|原因|
|---|---|
|**任何语音 / 音频播放**|完全无声版本|
|**菜单栏语音开关**|无音频功能|
|**视线追踪 / 眼球跟随**|真实照片素材无法自然实现|
|**窗口物理位移**|`walk` 只做原地视觉，不改变坐标|
|**全局鼠标 / 键盘监听**|不请求辅助功能权限|
|**小游戏完整实现**|**仅保留 ****`on_blank_click`**** 空钩子；点击空白区不作任何响应**|
|**点击穿透模式**|右键菜单需要整个窗口接收事件|
|**Windows 适配**|第一版仅 macOS|
|**任意拖拽物理**|无重力 / 碰撞|
|**`startled`**** 在非 ****`sleep`**** 状态下触发**|严格收窄为睡中唤醒|





## 附录：给 AI 的快速对齐摘要（可直接粘贴给 DSH / Workbuddy）



> 项目 PopoHere 是一个 macOS 桌宠，Python 3\.11 \+ PySide6，完全无声。第一版仅 macOS。状态机必须是纯 Python（不 import PySide6），素材通过 `theme.json` 解耦。共 9 个必需状态 \+ 1 个可选状态 `landed`。`idle` 5 秒后 30% 走 `walk` / 70% 睡 `sleep`。`dragging` 独立专用图，释放后进 `landed`（若有）或直接 `idle`。`startled` 仅在 `sleep` 被唤醒时触发。所有反馈靠图片 \+ 可选气泡，无音频。单击 \<5px / \<300ms，拖拽 ≥5px。右键任意位置出菜单，`menu` 状态需双重保障退出。小游戏只留 `on_blank_click` 空钩子。窗口用 `FramelessWindowHint` \+ `WA_TranslucentBackground` \+ `WindowStaysOnTopHint` \+ `Tool`。打包优先 `pyside6-deploy`，退回 PyInstaller 或源码分发。分模块生成，每轮只做一件事，生成后立即 `python main.py` 验证。
> 
> 





**请确认**：以上 v1\.0 PRD 是否完整覆盖了你的预期？确认后我们可以从**第一轮模块**（`theme.py` \+ `themes/default/theme.json`）开始，你复制给 DSH / Workbuddy 生成第一批代码，然后我们逐步往下走。

