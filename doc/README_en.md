<div align="center">

<img src="assets/icon.png" width="116" alt="PopoHere">

# PopoHere

**A cat that lives on your Mac desktop.**

Turn your own pet into a desktop companion — drop a few photos in a folder, and it does the rest.

[![macOS](https://img.shields.io/badge/macOS-11%2B-black?logo=apple&logoColor=white)](#install)
[![Version](https://img.shields.io/badge/version-2.0.0-8FAE9B)](#)
[![License](https://img.shields.io/badge/license-MIT-blue)](../LICENSE)
[![Dependencies](https://img.shields.io/badge/dependencies-none-success)](#)

[Install](#install) · [How to play](#how-to-play) · [Make your own](#make-your-own) · [中文](../README.md)

<img src="assets/hero.png" width="100%" alt="PopoHere on a Mac desktop">

</div>

---

## What it is

A macOS desktop pet. No Dock icon, no focus stealing, no network — it just sits on your screen:
breathing, wandering, falling asleep, flailing when you pick it up, and getting annoyed if you pet it too much.

The original is **Popo**, a British Shorthair (those are her photos). The whole app is **1.2 MB** with zero network code.

## Why it's not just a looping GIF

| | |
|---|---|
| 🧠 **An actual state machine** | idle / petting / annoyed / playing / sleeping / startled / landing, with cat-like probability transitions — not one animation on repeat |
| 🖐 **Drag that keeps up** | the window is moved natively using **screen coordinates**, not by chasing the cursor from JS — there's a classic feedback-loop trap here, see [ARCHITECTURE](ARCHITECTURE.md) |
| 🎲 **Multiple images per state** | drop several frames in a state; one is picked at random and locked until you leave and come back |
| ⏰ **Reminders don't need the cat** | a standalone popup fires even when the pet is hidden, with no audio and no animation |
| 🪶 **Zero dependencies** | Objective-C + one WebView, universal binary (Intel / Apple Silicon), starts in under half a second |
| 🎨 **Swap in your own pet** | no code changes — two commands regenerate every asset |

## Install

**Requires macOS 11 (Big Sur) or later.**

1. Download the latest zip from [Releases](../../releases)
2. Unzip and drag `PopoHere.app` into `/Applications`
3. Double-click to open

> [!IMPORTANT]
> This is a personal project without a paid Apple developer certificate, so **the first launch is blocked** by Gatekeeper.
> It's not malware: **right-click** (or Control-click) the app → **Open** → **Open** again. One time only.
>
> Or in a terminal:
> ```bash
> xattr -dr com.apple.quarantine /Applications/PopoHere.app
> ```

## How to play

| What you want | What to do |
|---|---|
| Move it | **Drag** the cat; let go and it lands on its own |
| Pet it | Click once; **10 rapid clicks** and it swipes at you |
| Wake it | Poke it while it's asleep |
| Do nothing | After 5 seconds it wanders off or flops down |
| Open the menu | **Right-click** the cat, or click the cat icon in the **menu bar** |
| See what it's doing | Open the status panel from the menu — you can preview every state |

Position and size are remembered between launches.

## Reminders

Right-click → **Reminders**. Three presets: **slack off 25 min / drink water 45 min / stretch 60 min**, all off by default.

- Time steps by **1 → 5 → 10 → 15…** (never 6 or 11)
- Each row has a **once / repeat** switch:
  - **Once** (default): fires once, then switches itself off
  - **Repeat**: keeps firing at the interval until you turn it off
- When due, a small panel appears in the **top-right corner**: `到时间了，请去喝口水！（7s）` — click **确认** to close, or it dismisses itself after 10 seconds
- **Multiple reminders stack**, and you choose which one to close first
- Works even when the pet is hidden

## Make your own

No coding required.

**① Prepare photos.** 8–16 shots of your pet, same camera and lighting if possible. Drop them into `source/origin_images/`:

```text
source/origin_images/
├── idle_1.png        idle (add more numbers for variety)
├── idle_2.png
├── touch_1.png       being petted
├── scratch_1.png     annoyed
├── sleep_1.png       sleeping
├── play_1.png        playing
├── dragging_1.png    picked up
├── logo_1.png        app icon
└── menubar_1.png     menu bar silhouette
```

Keep the background a **solid colour** — background removal is semantic segmentation, not a large model, and solid backdrops give the cleanest edges.
**The photo's orientation is what you get** — nothing is rotated or flipped for you. Full rules in [source/README.md](../source/README.md).

**② Run the preparation pipeline.**

```bash
pip install pillow rembg
python3 code/prepare/cutout.py --check     # validate naming first
python3 code/prepare/cutout.py             # cut out → normalize → bottom-align
python3 code/prepare/build_theme.py        # scan filenames into theme.json
```

**③ Rebuild.**

```bash
./code/build/build_app.sh --run
```

`code/build/dist/PopoHere.app` is now your own pet.

## Under the hood

```text
Objective-C shell (AppKit)
├── transparent borderless window + WKWebView
├── NSStatusItem menu bar / glass panels (NSVisualEffectView)
└── NSEvent local monitor → screen-coordinate dragging

Web layer (vanilla JS, no framework)
├── func_state    state machine (pure logic, no DOM → testable in Node)
├── func_render   state → sprite / motion / bubble
├── func_input    hit testing, click vs drag
└── func_menu     panel UI

Preparation (Python + rembg)
└── cutout → normalize → per-state size matching → theme.json
```

<details>
<summary><b>Development & tests</b></summary>

```bash
# Browser preview with a debug panel
python3 code/build/build_web.py && open code/build/out/preview.html

# Tests: state machine 58 · rapid clicks 9 · dragging 7 · reminder store 16
node code/test/state_machine_test.js
python3 code/test/click_mash_test.py
python3 code/test/drag_tracking_test.py
clang -fobjc-arc -framework Foundation -I code/core/func_reminder \
  code/test/reminder_store_test.m code/core/func_reminder/PHReminder.m -o /tmp/remtest && /tmp/remtest

# Build / package
./code/build/build_app.sh
python3 code/build/package_release.py
```

Before touching the code, read [AGENTS.md](../AGENTS.md); design decisions and traps are in [ARCHITECTURE.md](ARCHITECTURE.md), the full spec in the [PRD](PRD/PRD.md).

</details>

## FAQ

**Where did the cat go?** Menu bar icon → "Show Popo". Hiding is not quitting.

**Why is the first launch blocked?** No Apple developer certificate — see Install above.

**Does it upload anything?** No. There is no networking code and it doesn't read your files.

**Windows support?** No, this build is a native AppKit shell.

**Are the cat photos in the repo?** No. Only the processed sprites are; originals stay local.

---

<div align="center">

The cat is real. The code is open source. Go make it yours.

[MIT](../LICENSE) · [中文](../README.md)

</div>
