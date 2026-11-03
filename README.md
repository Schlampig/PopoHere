<div align="center">

<img src="doc/assets/icon.png" width="116" alt="PopoHere">

# PopoHere

**让可爱的 Popo 猫住进你的 Mac 桌面～**

让 Popo 猫成为你的桌宠及小助手。或用你自己的宠物伙伴做一只桌宠——只需拍几张照片丢进文件夹，剩下交给 Popo。

[![macOS](https://img.shields.io/badge/macOS-11%2B-black?logo=apple&logoColor=white)](#如何获取)
[![Version](https://img.shields.io/badge/version-2.0.0-8FAE9B)](#)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Dependencies](https://img.shields.io/badge/dependencies-none-success)](#)

[如何获取](#如何获取) · [怎么使用](#怎么使用) · [如何改造](#如何改造) · [English](doc/README_en.md) · [MIT](LICENSE)

<img src="doc/assets/concept.png" width="100%" alt="PopoHere 概念预览">

<sub>注意：概念预览图，真实效果略有不同。</sub>

</div>

---

## 谁是 Popo

PopoHere 是一个 macOS 桌面宠物。不占 Dock、不抢焦点、不联网，就静静待在你的屏幕上——会呼吸、会溜达、会趴下睡觉，被你拎起来的时候四脚乱蹬，撸久了会翻脸。

这是开发者在大模型 DeepSeek V4.1-flash-1017、Hy4 preview、Seedream4.5 及 Workbuddy 协助下，为自家可爱的（重达 7kg，减肥中）美国短毛猫 Pocky（昵称 Popo）制作的轻量级桌宠应用。Popo 是一个安静、治愈的孩子，当我们在桌前办公时，她会静静爬上自己专属的塑料小红椅子，在上面打盹，或仅仅是沉静地看着我们。希望通过这个小项目，让更多人和 Popo 做朋友。

## PopoHere 的有趣亮点

| | |
|---|---|
| 🧠 **真的是个状态机** | 静息 / 被撸 / 挠人 / 自娱 / 睡觉 / 惊醒 / 落地，按猫的天性用概率流转；不是一段动画循环播到底 |
| 🖐 **拖拽跟手** | 窗口位移由原生层用**屏幕坐标**同步跟踪，不靠 JS 追光标——这里面有个经典的反馈环坑，见[用户指南](doc/UserGuide.md#拖拽一个必须注意的坐标系问题) |
| 🎲 **一个状态多张图** | 同一状态放几张素材，每次进入随机抽一张并锁定，猫不会永远保持同一个姿势 |
| ⏰ **提醒不依赖猫** | 到点弹独立小窗，**猫被隐藏、没有音频、没有动画都不影响** |
| 🪶 **零依赖** | Objective-C + 一个 WebView，通用二进制（Intel / Apple 芯片），启动不到半秒 |
| 🎨 **可以换成你的宠物** | 换图不用改代码，跑几条命令重新生成 |

## 如何获取

**需要 macOS 11 (Big Sur) 或更高。**

1. 到 [Releases](../../releases) 下载最新的 zip
2. 解压，把 `PopoHere.app` 拖进「应用程序」
3. 双击打开

> [!IMPORTANT]
> 这是个人项目，没有向苹果付费签名，**第一次打开会被系统拦一下**。
> 这不是中毒：**右键**（或 Control + 点击）应用图标 → 选「打开」→ 再点一次「打开」，**只需一次**，之后永久正常。
>
> 或者一行命令解决：
> ```bash
> xattr -dr com.apple.quarantine /Applications/PopoHere.app
> ```

系统要求、安装细节与拦截提示的处理方式，详见[用户指南 1.1 安装与启动](doc/UserGuide.md#11-安装与启动)。

## 怎么使用

**和它互动**

| 你想做的事 | 怎么操作 |
|---|---|
| 撸它 | 点一下；**连着猛点 10 下**它会翻脸挠你 |
| 换个地方 | 按住猫**拖动**，松手它会自己落地 |
| 叫醒它 | 睡着时随便戳一下 |
| 什么都不做 | 5 秒后自己溜达，或者趴下睡觉 |
| 打开菜单 | **右键**猫，或点**菜单栏**的小猫图标 |

**定时提醒**

右键 →「定时提醒」，三条预置：**摸鱼 25 分钟 / 喝水 45 分钟 / 久坐拉伸 60 分钟**，默认全关。
每条可设 **一次**（响过即止）或 **间隔**（按间隔循环到你关掉），到点在**屏幕右上角**弹出小窗，
点「确认」关闭，不理它 10 秒后自动消失；几条同时到点会叠在一起，猫被隐藏时也照样提醒。

**待办清单**

右键 →「待办清单」，最多 10 条、每条 50 字，勾选完成、随时清空，保存在本地。

完整的按键说明、默认取值与状态含义，详见[用户指南 1.3 功能介绍](doc/UserGuide.md#13-功能介绍)。

## 如何改造

本项目完全开源架构与代码，你可以基于此进行二次开发，也可以用当前的代码、自己准备素材构建自己的桌宠，不需要会写代码。以下是快速步骤：

**① 准备照片。** 拍 8–16 张你的宠物，尽量同一机位、同一灯光。放进 `source/origin_images/`，按状态命名：

```text
source/origin_images/
├── idle_1.png        静息（同一状态多张就加序号，运行时随机抽）
├── idle_2.png
├── touch_1.png       被撸
├── scratch_1.png     不高兴
├── sleep_1.png       睡觉
├── play_1.png        自己找事做
├── dragging_1.png    被拎起来
├── logo_1.png        应用图标
└── menubar_1.png     菜单栏剪影
```

背景尽量用**纯色**（白墙、纯色地板）——预处理是语义分割，不是大模型，纯色背景下边缘最干净。
**照片的方向就是最终效果**——程序不旋转、不翻转，你给什么姿势就摆什么姿势。

**② 跑预处理。**

```bash
pip install pillow rembg
python3 code/prepare/cutout.py --check     # 先只校验命名
python3 code/prepare/cutout.py             # 抠图 → 统一画布 → 底部对齐
python3 code/prepare/build_theme.py        # 扫文件名生成 theme.json
```

**③ 重新构建。**

```bash
./code/build/build_app.sh --run
```

`code/build/dist/PopoHere.app` 就是你的专属桌宠。

素材规格、扩展名与命名规则、环境准备与常见报错，详见[用户指南 2.1 制作步骤](doc/UserGuide.md#21-制作步骤)。

## 常见问题

**猫不见了？** 菜单栏图标 →「显示 Popo」。隐藏不等于退出。

**为什么第一次打开被拦？** 没有苹果开发者签名，见上面的安装说明。

**会上传我的东西吗？** 不会。没有网络代码，不读你的文件，就是一个画猫的透明窗口。

**能用在 Windows 上吗？** 不能，这一版是 AppKit 原生外壳。

**猫的照片会进仓库吗？** 不会。仓库里只有处理后的贴图，原始照片留在本地。

---

<div align="center">

愿 Popo 陪你度过宁静充实、灵感迸发的每一天。

</div>
