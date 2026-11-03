# PopoHere User Guide

[简体中文](UserGuide.md) · **English**

This document has two parts: **Chapter 1 is for people who just want to use the desktop pet**,
**Chapter 2 is for people who want to build their own**. The two parts are independent,
so jump to whichever you need.

## Contents

**Part 1 · Using PopoHere**

- [1.1 Installation and Launch](#11-installation-and-launch)
  - [1.1.1 Requirements](#111-requirements)
  - [1.1.2 Installation Steps](#112-installation-steps)
  - [1.1.3 System Prompt](#113-system-prompt)
- [1.2 Interactions](#12-interactions)
- [1.3 Features](#13-features)
  - [1.3.1 Reminders](#131-reminders)
  - [1.3.2 To-do List](#132-to-do-list)
  - [1.3.3 Show / Hide the Pet](#133-show--hide-the-pet)
  - [1.3.4 Show / Hide the Status Panel](#134-show--hide-the-status-panel)
  - [1.3.5 Size](#135-size)
  - [1.3.6 Launch at Login](#136-launch-at-login)
  - [1.3.7 Sound](#137-sound)
  - [1.3.8 Open Assets Folder / Reset Position](#138-open-assets-folder--reset-position)
  - [1.3.9 About and Quit](#139-about-and-quit)
- [1.4 FAQ](#14-faq)

**Part 2 · Build Your Own**

- [2.1 Steps](#21-steps)
  - [2.1.1 Prepare Assets](#211-prepare-assets)
  - [2.1.2 Prepare the Environment](#212-prepare-the-environment)
  - [2.1.3 Run the Preparation Pipeline](#213-run-the-preparation-pipeline)
  - [2.1.4 Rebuild](#214-rebuild)
  - [2.1.5 Architecture](#215-architecture)

---

# Part 1 · Using PopoHere

## 1.1 Installation and Launch

### 1.1.1 Requirements

| Item | Requirement |
|---|---|
| Operating system | macOS 11 (Big Sur) or later |
| Processor | Intel or Apple silicon (universal binary) |
| Disk usage | About 1.2 MB |
| Runtime dependencies | None. Python, Node and any third-party library are not required |

**Privacy and resource usage**:

- **Fully offline.** There is no networking code in the app; it never contacts a server
  and never checks for updates.
- **No data is uploaded.** It does not read your documents, photos, clipboard or keystrokes.
- **No token usage, no API calls.** All behaviour is decided by a local state machine and
  has nothing to do with any large-model service.
- **A single background process.** When idle it runs one timer per second (for reminders
  and state timing); it does not poll the disk or the network.
- Preferences live in `~/Library/Preferences/com.popohere.pet.plist`, and the to-do list in
  `~/Library/Application Support/PopoHere/checklist.json`. Both can be deleted manually
  after removing the app.

### 1.1.2 Installation Steps

1. Open the repository's **Releases** page and download the latest `PopoHere-<version>.zip`.
2. Unzip it. The `PopoHere-<version>` folder contains `PopoHere.app`,
   `启动 PopoHere.command` and a short readme.
3. Drag `PopoHere.app` into `/Applications` (running it in place works too, but
   Applications is easier to find later).
4. Double-click `PopoHere.app`.

After launch:

- A small cat silhouette appears in the **menu bar** at the top-right of the screen;
- The pet appears in the **bottom-left corner** of the screen;
- The app **does not appear in the Dock** and does not steal focus.

> If nothing happens after double-clicking, see the next section.

### 1.1.3 System Prompt

On first launch, macOS may show:

> "PopoHere" cannot be opened because Apple cannot check it for malicious software.

**Why**: the app is not signed with a paid Apple developer certificate; it is only
ad-hoc signed locally. macOS shows this generic warning for every app that has not been
notarised. It says nothing about what the app actually does.

**How to open it (pick one; only needed once)**:

| Method | Steps |
|---|---|
| Right-click (recommended) | In Finder, **right-click** (or Control-click) `PopoHere.app` → choose **Open** → click **Open** again in the dialog |
| System Settings | After the block, open **System Settings → Privacy & Security** and click **Open Anyway** at the bottom |
| Terminal | `xattr -dr com.apple.quarantine /Applications/PopoHere.app` |

Once it has opened successfully, macOS remembers the decision and double-clicking works
from then on.

> The zip also contains `启动 PopoHere.command`, which clears the quarantine flag and
> launches the app. That script may itself be blocked the first time; handle it the same way.

## 1.2 Interactions

The pet's behaviour is driven by a local state machine that switches states based on your
actions and the passage of time. In the table below, "mouse" means an external mouse and
"trackpad" means the built-in trackpad.

| What you want | Mouse | Trackpad | What the pet does |
|---|---|---|---|
| Pet it | **Click** on it | **Tap** with one finger | Enters the "being petted" state |
| Annoy it | **Click 10 times quickly** | **Tap 10 times quickly** | Snaps on the 10th click and enters the "annoyed" state |
| Pick it up | **Press and drag** | **Press and drag** with one finger | Lifted and follows the cursor; lands when released |
| Wake it | Click while it is asleep | Tap once | Startles, then returns to idle |
| Do nothing | — | — | After 5 seconds it goes off to play or lies down to sleep |
| Open the menu | **Right-click** it | **Two-finger tap** (right-click) | The menu panel appears |
| Open the menu (alternative) | Click the cat icon in the **menu bar** | Same | The system menu appears |

A few notes:

- **Click vs. drag**: a press counts as a click only if it moves less than 12 px and lasts
  shorter than 300 ms; otherwise it is treated as a drag. The same threshold applies to the
  trackpad, so normal taps are never mistaken for drags.
- **Petting counter**: consecutive pets count only if the gap between them is at most
  4 seconds; pausing longer resets the counter. After 10 pets it snaps and enters a
  6-second cooldown during which further clicks do nothing.
- **The status panel** shows "连撸 N/10" (pets in a row) in real time, so you can see how
  close you are.
- **Idle branching**: after 5 idle seconds there is a 35% chance it goes off to play and a
  65% chance it lies down to sleep. This matches cat behaviour; it can be tuned in
  `theme.json` for other kinds of pets.
- **Position and size are remembered** between launches.

## 1.3 Features

The menu can be opened in two ways. Both show the same items and stay in sync:

- **Right-click the pet**: a glass panel appears at the cursor;
- **Menu bar icon**: a system menu appears at the top of the screen.

Each feature below is described as: how to open it → what the controls are → how to set it →
what happens → default value → other notes.

### 1.3.1 Reminders

**How to open**
Right-click the pet → **Reminders**; or the menu bar icon → **Reminders**.
If the menu is already open, click the item directly.

**Controls**

| Position | Element | Purpose |
|---|---|---|
| Far left of each row | Round switch | Master switch for that reminder |
| Middle | `−` / minutes / `+` | Adjust the interval |
| Far right of each row | `Once` / `Repeat` | Fire once and stop, or repeat on the interval |

**How to set it**

1. Use `+` / `−` to reach the interval you want. Values step through legal positions:
   **1 → 5 → 10 → 15 → 20 …**, up to 180 minutes. Going down, 5 goes straight back to 1.
2. Choose the mode: **Once** (default) or **Repeat**.
3. Turn on the master switch at the far left.

**What happens**

When a reminder is due, a panel appears in the **top-right corner** of the screen:

```
摸鱼结束，接着干活~（7s）
         [ 确认 ]
```

- Clicking **确认** closes it immediately;
- If ignored, it closes itself when the countdown in brackets reaches zero (10 seconds);
- One reminder firing and closing means "this round is over": in **Once** mode the master
  switch turns itself off, in **Repeat** mode the timer restarts until you turn it off;
- When several reminders are due at the same time they **stack in the same panel**, each with
  its own countdown and its own confirm button, so you decide which to dismiss first.

**Defaults**

| Item | Interval | Message | Switch | Mode |
|---|---|---|---|---|
| 摸鱼 (slack off) | 25 min | 摸鱼结束，接着干活~ | Off | Once |
| 喝水 (drink water) | 45 min | 到时间了，请去喝口水！ | Off | Once |
| 久坐拉伸 (stretch) | 60 min | 到时间了，请去拉伸一下！ | Off | Once |

**Other notes**

- Reminders **do not depend on the pet**: they still fire while the pet is hidden, and they
  need neither sound nor animation.
- The popup does not take keyboard focus, so typing in other apps is not interrupted.
  A single click on 确认 is enough.
- Reminders stop when the app quits; on the next launch the saved intervals are used again.

### 1.3.2 To-do List

**How to open**
Right-click the pet → **To-do list**; or the menu bar icon → **To-do list**.

**Controls**

| Element | Purpose |
|---|---|
| Round checkbox | Mark as done / undone |
| Item text (click) | Edit that item |
| **+ Add** at the bottom | Add a new item |
| **Clear** at the bottom | Delete all items; asks for confirmation |

**How to set it**

1. Click **+ Add**, type the content and press Return;
2. Click an item's text to edit it, press Return again to save;
3. Click the checkbox of a finished item; completed text is shown with a strikethrough.

**What happens**

- Items are written to a local file immediately and survive restarts;
- When every item is checked, the pet performs a short celebration.

**Defaults**

- At most **10 items**, each at most **50 Chinese characters** (longer input is truncated);
- The list starts empty.

**Other notes**

- The to-do list and reminders are independent of each other;
- Data is stored in `~/Library/Application Support/PopoHere/checklist.json` and can be
  backed up or migrated directly.

### 1.3.3 Show / Hide the Pet

**How to open**
Right-click the pet → **Show / Hide pet**; or the menu bar icon → the same item.

**Controls**
A toggle: each click flips the state.

**How to set it**
Nothing to configure.

**What happens**

- Once hidden, the pet disappears from the desktop but the app **keeps running** and the
  menu bar icon remains;
- Clicking again restores it at the position it had before hiding.

**Default**
The pet is shown at launch.

**Other notes**

- **Hiding is not quitting.** Use **Quit** to end the app.
- While the pet is hidden, the right-click menu and the status panel are dismissed too;
  reminders keep working.

### 1.3.4 Show / Hide the Status Panel

**How to open**
Right-click the pet → **Show / Hide pet status**; or the menu bar icon → the same item.

**Controls**
The status panel is a floating window at the bottom-right corner with three parts:

| Area | Purpose |
|---|---|
| **✕** at the top right | Close the panel |
| State list | Click a state name to preview that state's sprite and motion immediately |
| Footer | Current state, petting counter, and time spent in the current state |

**How to set it**

- Click a state name to preview it; the preview plays once and then returns to **menu** or
  **idle**;
- Drag the title area to move the panel anywhere;
- The panel resizes to its content and is kept inside the screen.

**What happens**

- Previews never write to the petting counter and never trigger the annoyed state;
- If the right-click menu is open, the pet returns to **menu standby** after the preview
  instead of dropping to idle.

**Default**
The panel is **not** opened automatically at launch; it must be enabled manually.
The enabled state is remembered only for the current session's hide/show cycle.

**Other notes**

- The status panel is subordinate to the pet: hiding the pet also hides it, and while the
  pet is hidden this menu item is greyed out;
- When the pet is shown again, a previously enabled panel is restored.

### 1.3.5 Size

**How to open**
Right-click the pet → **Size**; or the menu bar icon → **Size**. A submenu expands.

**Controls**
`160 px` / `220 px` / `300 px` / `380 px`; the current size is checkmarked.

**How to set it**
Click a size; it applies immediately.

**What happens**
The sprite scales proportionally and the hit area scales with it. Menu and reminders are
unaffected.

**Default**
`220 px`.

**Other notes**
The chosen size is written to preferences and reused on the next launch.

### 1.3.6 Launch at Login

**How to open**
Right-click the pet → **Launch at login**; or the menu bar icon → the same item.

**Controls**
A toggle with a checkmark on the right.

**How to set it**
Click once to enable or disable.

**What happens**
Enabling writes a login item to `~/Library/LaunchAgents/` so PopoHere starts automatically
when you log in; disabling removes it.

**Default**
Off.

**Other notes**
If you delete the app, turn this off first so no stale login item points at a missing path.

### 1.3.7 Sound

**How to open**
Right-click the pet → **Sound**; or the menu bar icon → **Sound**.

**Controls**
`On` / `Off`.

**Current state**
This version ships **without audio assets**, so the whole **Sound** item is **greyed out**.
That is expected behaviour, not a fault.

**Other notes**
If you prepare and wire up audio assets yourself, the item becomes available once assets are
detected.

### 1.3.8 Open Assets Folder / Reset Position

**Open assets folder**
Opens the asset directory inside the app bundle in Finder so you can inspect the sprites in
use. Read-only; no file is modified.

**Reset position**
Moves the pet back to its default position (bottom-left corner). Useful when the pet has
been dragged off-screen or is permanently covered by another window.

### 1.3.9 About and Quit

**About PopoHere**
Opens the project page in your browser, where you can read the changelog, report issues or
contribute.

**Quit**
Ends the process. The current position and preferences are saved beforehand.

> Note: if the menu bar icon is crowded out by other icons, hold `⌘` and drag icons to
> reorder them.

## 1.4 FAQ

**The pet is gone.**
Check whether the menu bar icon is still there. If **Show / Hide pet** is in the hidden
state, one click brings it back. You can also use **Reset position** to move it to the
bottom-left corner.

**Why was the first launch blocked?**
Because the app is not signed with an Apple developer certificate.
See [1.1.3](#113-system-prompt).

**Does it go online or upload anything?**
No. There is no networking code in the app, and it does not read your personal files.

**Does it run on Windows or Linux?**
No. This version is a native macOS shell (AppKit + WKWebView) and relies on macOS-only APIs.

**Why does it look different each time it enters the same state?**
When a state has several sprites, one is picked at random and locked until the pet leaves
that state and comes back. This keeps the pet from holding one pose for too long.

**I clicked and nothing happened.**
First make sure you clicked the pet itself rather than the transparent area around it.
Also, after 10 rapid clicks the pet enters the "annoyed" state, during which further clicks
are ignored by design.

**I clicked many times but it never gets annoyed.**
Gaps longer than 4 seconds reset the counter. The status panel footer shows the current
count as "连撸 N/10".

**A reminder fired but I did not see it.**
The popup is fixed to the top-right corner and closes itself after 10 seconds. If you were
in a full-screen app, the popup appears in that space; exit full screen and check again.

**Do the cat photos end up in the repository?**
The repository contains only the **first photo of each state** as an example, to illustrate
how assets are organised. All other originals and intermediate artefacts stay local.

---

# Part 2 · Build Your Own

The architecture, code and asset pipeline are fully open. You can:

- Use the existing code with your own assets to build **your own desktop pet** (no coding
  required), or
- Build on top of the code and extend it with new states, feature modules or interactions.

The steps below go from **prepare assets → prepare environment → run the pipeline →
rebuild**, followed by an architecture overview for deeper changes.

## 2.1 Steps

### 2.1.1 Prepare Assets

Assets live under `source/`:

```
source/
├── origin_images/     original photos (the source of sprites)
└── origin_audios/     original audio (may be empty)
```

**Naming rule**

```
<state>_<index>.png
```

- Index starts at 1; add as many as you have for that state;
- With a single image the index can be omitted (`idle.png`), but including it is recommended
  so that adding more later does not require renaming;
- PNG / JPG are both accepted; backgrounds are removed automatically.

**Which states are needed**

| State | Meaning | Suggested count |
|---|---|---|
| `idle` | at rest | 3–4 |
| `touch` | being petted | 4–6 |
| `scratch` | annoyed | 2–3 |
| `play` | amusing itself | 4–6 |
| `sleep` | sleeping | 3–4 |
| `dragging` | picked up | 2 |
| `menu` | sitting up (while the menu is open) | 1–2 |
| `startled` | startled awake | 1–2 |
| `landed` | landing | 1–2 |

There are also two non-state assets:

| Purpose | File name | Notes |
|---|---|---|
| App icon / panel logo | `logo_1.png` | A clear face or outline works best |
| Menu bar icon | `menubar_1.png` | Any pose; the pipeline turns the alpha channel into a black silhouette |

**Photography tips**

**① Keep the background a solid colour.**
The pipeline uses rembg (u2net) for semantic segmentation, which works best on
"one subject + a clean background". A plain wall, plain floor or plain sofa cover is ideal.
Patterned wallpaper, cluttered rooms, or other pets and people in frame tend to leave
fringes or residue, and there is no retry mechanism.

**② Keep the same camera position and lighting.**
When the pet switches between states, its body size and ground line must line up, otherwise
the change looks like a jump.

**③ For multiple images of one state, change only the expression and pose — do not move
the pet.**

**④ The photo's orientation is the final orientation; nothing is rotated for you.**
The pipeline only removes the background, crops to the subject and scales it into a uniform
canvas. It never rotates or flips. If a photo looks sideways in Finder, it will look
sideways on the desktop too, so correct it in an image editor first.

**⑤ Keep the subject roughly the same size in frame.**
Multiple images of one state are aligned by visual area (shrinking only, never enlarging),
but photos taken at very different focal lengths can still differ noticeably.

### 2.1.2 Prepare the Environment

| Dependency | Version | Purpose |
|---|---|---|
| macOS | 11+ | Running and building |
| Xcode Command Line Tools | any recent version | Provides `clang`, `iconutil`, `codesign` |
| Python | 3.9+ | Runs the preparation and build scripts |
| Pillow | latest | Image processing |
| rembg | latest | Background removal (downloads the u2net model, ~170 MB, on first run) |
| Google Chrome | any recent version | Only needed for the front-end regression tests |

Install:

```bash
xcode-select --install          # if the command line tools are not installed yet
pip3 install pillow rembg
```

Verify:

```bash
clang --version
python3 -c "import PIL, rembg; print('ok')"
```

### 2.1.3 Run the Preparation Pipeline

The pipeline converts original photos into sprites, in three steps.

**Step 1: validate names (no model, takes seconds)**

```bash
python3 code/prepare/cutout.py --check
```

Expected output:

```
共 18 张原图，覆盖 9 个状态：
  dragging   1 张
  idle       3 张
  ...
命名校验通过
```

**Step 2: remove backgrounds and normalise**

```bash
python3 code/prepare/cutout.py
```

Expected output, one line per image, then a QA sheet:

```
OK  idle_1           (2304, 1728) -> (640, 640)  (0.8s)
...
    归一 idle_2         ×0.87
OK  tray_icon.png（菜单栏模板图标）
QA 总览图: code/build/out/qa_sheet.png
```

**Where the output goes**

| Output | Location | Notes |
|---|---|---|
| Transparent sprites | `code/pet_images/*.png` | Uniform 640×640 canvas, bottom-aligned |
| Menu bar icon | `code/pet_others/tray_icon.png` | 44×44, black + alpha |
| QA sheet | `code/build/out/qa_sheet.png` | Open it to check the cut-out quality by eye |

**Step 3: generate the state contract**

```bash
python3 code/prepare/build_theme.py
```

This scans the file names in `pet_images/` and writes `theme.json`, the mapping between
states and sprites. You do not need to write this file by hand when swapping assets; edit it
only when tuning behaviour parameters (probabilities, thresholds).

**Troubleshooting**

| Symptom | Cause and fix |
|---|---|
| `ModuleNotFoundError: rembg` | Dependencies missing; run `pip3 install rembg` |
| First run stalls for minutes | The u2net model is being downloaded; it is cached in `~/.u2net/` afterwards |
| "以下文件不符合命名规范" is reported | The file name contains Chinese characters, spaces or extra suffixes; rename to `<state>_<index>.png` |
| A state has no assets | That state falls back to other available sprites at runtime; add the missing images |
| Edges look frayed | The original background is too busy; re-shoot against a solid colour |
| Sprite sizes jump between frames | Camera positions differ too much within one state; see points ② and ⑤ in [2.1.1](#211-prepare-assets) |

> Note: `cutout.py` **deletes** sprites in `code/pet_images/` that no longer correspond to
> any original image, keeping the theme consistent with the actual assets. The example
> sprites shipped with the repository are overwritten as well; restore them with
> `git checkout code/pet_images` if needed.

### 2.1.4 Rebuild

**Build the app**

```bash
./code/build/build_app.sh          # output: code/build/dist/PopoHere.app
./code/build/build_app.sh --run    # build and launch
```

The build inlines the page, compiles both architectures, merges them into a universal
binary, assembles the bundle, re-signs it ad-hoc and verifies the signature.

Expected output:

```
完成：/path/to/code/build/dist/PopoHere.app
```

**Package a release**

```bash
python3 code/build/package_release.py
```

Output: `code/build/releases/PopoHere-<version>.zip`, containing the app, the launcher
script and the usage notes.

**Browser preview (faster when working on the front end)**

```bash
python3 code/build/build_web.py
open code/build/out/preview.html
```

The preview build includes a debug panel: force any state, show hit areas, change size.

**Troubleshooting**

| Symptom | Cause and fix |
|---|---|
| `clang: error: ...` | Command line tools missing; run `xcode-select --install` |
| Builds fine but macOS says the app is damaged | The signature was invalidated after resources were copied; re-running `build_app.sh` re-signs and verifies |
| First launch is blocked | The app is not notarised; see [1.1.3](#113-system-prompt) |
| Front-end changes do not show up | The app embeds a build artefact; re-run `build_web.py` and `build_app.sh` |

**Running the tests** (recommended after changing the state machine, input handling or
reminders)

```bash
node code/test/state_machine_test.js      # state machine logic, 58 assertions
python3 code/test/click_mash_test.py      # rapid-click behaviour, 9 assertions (needs Chrome)
python3 code/test/drag_tracking_test.py   # drag detection, 7 assertions (needs Chrome)

clang -fobjc-arc -framework Foundation -I code/core/func_reminder \
  code/test/reminder_store_test.m code/core/func_reminder/PHReminder.m \
  -o /tmp/remtest && /tmp/remtest          # reminder timing semantics, 16 assertions
```

### 2.1.5 Architecture

#### In one sentence

> A borderless transparent NSWindow with a WebView inside; every behaviour of the pet is
> driven by a JavaScript state machine running in that page.

```
┌─────────────────────────────────────────────┐
│  PopoHere.app                               │
│  ┌───────────────────────────────────────┐  │
│  │ func_window  (Objective-C)            │  │
│  │  · borderless transparent NSWindow,   │  │
│  │    always on top, no Dock icon        │  │
│  │  · menu bar NSStatusItem              │  │
│  │  · drag: NSEvent monitor → screen     │  │
│  │    coordinates                        │  │
│  │  · position / size / view → defaults  │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │ WKWebView                       │  │  │
│  │  │  func_state   state machine     │  │  │
│  │  │  func_render  state → sprite    │  │  │
│  │  │  func_input   hit test / click  │  │  │
│  │  │  func_menu    menu bridge/page  │  │  │
│  │  │  main         wiring + loop     │  │  │
│  │  └─────────────────────────────────┘  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

#### Technology choice

The shell uses `clang + Objective-C + WebKit`: no third-party dependencies, roughly 1.2 MB
on disk, launches in well under half a second, and lets the interface be built with web
technologies. Keeping the interaction logic in JavaScript has a practical benefit too:
changing behaviour does not require recompiling the native shell — `build_web.py` finishes
in milliseconds and the result is visible directly in a browser.

#### Module responsibilities

| Module | Location | Responsibility | Boundary |
|---|---|---|---|
| `func_state` | `code/core/func_state/` | State transitions, probabilistic visual choice, click/drag semantics | No DOM access, no globals |
| `func_render` | `code/core/func_render/` | State → sprite / motion / bubble | Does not change state or handle the mouse |
| `func_input` | `code/core/func_input/` | Hit areas, click vs. drag | Does not decide which state to enter |
| `func_menu` | `code/core/func_menu/` | Right-click menu bridge, panel page (`panel.html`) | Does not manage windows |
| `main` | `code/core/main.js` | Wiring, main loop, size and position, external API | Holds no business logic |
| `func_window` | `code/core/func_window/` | Window, menu bar, drag tracking, persistence, script bridge | Does not manage pet state |
| `func_reminder` | `code/core/func_reminder/` | Reminder timing (`PHReminder`) and the due popup (`PHAlert`) | Does not handle visual details |
| `func_checklist` | `code/core/func_checklist/` | To-do storage | Does not render the interface |

The state machine references no DOM API, which is why it can be unit-tested directly with
Node. Keeping that boundary is recommended: it is the only part that can be regression
tested without a graphical interface.

#### Data flow

```
theme.json ──┐
             ├─→ build_web.py ─→ a single inlined index.html ─→ WKWebView
pet_images ──┘                     (images become base64 webp)

user input ─→ func_input ─→ PetStateMachine ─→ func_render ─→ DOM
                 │                ↑
                 └─ native mode ──→ func_window (moves the window in screen coordinates)
```

#### Dragging: a coordinate-system trap worth knowing

**Symptom**: while dragging, the image shakes violently and lags behind the cursor.

**Root cause**: if JavaScript computes the offset from `e.clientX` and then asks the native
window to follow, a feedback loop appears — `clientX` is relative to the page viewport, and
the window being moved is exactly what carries that viewport:

```
cursor moves right 10px → window moves right 10px → cursor is 10px back inside the viewport
→ offset becomes zero → window is pulled back → repeat
```

**Current design**:

1. **All window movement happens natively.** On press, an `NSEvent` local monitor is installed
   and `[NSEvent mouseLocation]` (screen coordinates) drives `setFrameOrigin` in the same
   moment the event arrives — the same mechanism used when dragging a window by its title
   bar, with no cross-process round trip.
2. **The page also uses `e.screenX / e.screenY` for its threshold test.** This step is
   required: once movement is native, a page still using `clientX` would see the offset stay
   near zero, the state machine would never enter the dragging state, and releasing would be
   mistaken for a click.
3. **In native mode the page sends no movement messages at all**, only `press` and `release`.

**Regression test**: `code/test/drag_tracking_test.py` constructs exactly the
"`clientX` constant, `screenX` increasing" situation to lock this behaviour in.

#### theme.json: the state/sprite contract

```jsonc
{
  "behavior": {                    // global behaviour parameters
    "idle_duration_sec": 5,        // idle time before natural branching
    "idle_to_play_probability": 0.35, // chance to go play; the rest goes to sleep
    "touch_repeat_window_sec": 4,  // window for counting consecutive pets
    "touch_scratch_threshold": 10, // count at which it gets annoyed
    "scratch_cooldown_sec": 6,     // cooldown after being annoyed
    "click_max_drift_px": 12,      // below this movement it is a click
    "click_max_duration_ms": 300,  // below this duration it is a click
    "menu_timeout_sec": 120,       // fallback if the menu never closes
    "preview_duration_sec": 6      // duration of a status preview
  },
  "states": {
    "idle": {
      "visuals": ["idle_1.png", "idle_2.png"],  // picked at random and locked on entry
      "loop": true,
      "duration": 1.5,             // seconds for non-looping states
      "motion": "breathe",         // none / breathe / breathe-slow / bob-walk / shake / float / drop
      "bubble": "💤"               // optional bubble text
    }
  },
  "hitBoxes": {
    "body": { "x": 0.06, "y": 0.04, "w": 0.88, "h": 0.92 }  // relative, origin at top-left
  }
}
```

`motion` adds a CSS animation to still sprites, which removes the need for frame-by-frame
assets; `bubble` uses text or emoji rather than images for the same reason. Both fields can
be adapted to other kinds of pets — for a reptile, for instance, slow the breathing down and
drop the bubbles.

#### Build pipeline

```
source/origin_images/*.png
        │  code/prepare/cutout.py        background removal + normalisation (~1 s/image)
        ▼
code/pet_images/*.png  +  theme.json    the state/sprite contract
        │  code/build/build_web.py       inline JS modules + sprites as base64 webp
        ▼
code/build/out/native.html              single-file page
        │  code/build/build_app.sh       clang both architectures → lipo → assemble → ad-hoc sign
        ▼
code/build/dist/PopoHere.app            about 1.2 MB
        │  code/build/package_release.py zip + launcher script
        ▼
code/build/releases/PopoHere-<version>.zip
```

Sprites are inlined as data URIs during `build_web.py`, so the app bundle contains no second
copy of `pet_images`.

#### Signing and distribution

- The build ends with `codesign --force --sign -` (ad-hoc) followed by verification.
  Signing must happen after the bundle is assembled, otherwise macOS reports
  "code has no resources but signature indicates they must be present".
- The app is not notarised, so users must right-click → Open on first launch.
  See [1.1.3](#113-system-prompt).
- Do not pass `--sequesterRsrc` to `ditto` when packaging: the bundle has no resource fork,
  and the flag only adds a `__MACOSX` directory.

#### Directory layout

```
PopoHere/
├── source/
│   ├── origin_images/        original photos
│   └── origin_audios/        original audio (reserved)
├── code/
│   ├── prepare/              preparation scripts
│   ├── pet_images/           processed sprites + theme.json
│   ├── pet_audios/           processed audio (reserved)
│   ├── pet_others/           app icon, menu bar silhouette
│   ├── core/                 the pet itself (independent of appearance)
│   │   ├── main.js
│   │   ├── func_state/  func_render/  func_input/  func_menu/
│   │   ├── func_reminder/  func_checklist/
│   │   └── func_window/
│   ├── build/                build and packaging scripts
│   ├── test/                 tests
│   └── prototype/            page shell template
├── doc/                      documentation (this file, README, PRD)
└── README.md  AGENTS.md  LICENSE
```

When adding a feature, create a new `func_<name>/` directory under `code/core/` and keep the
same boundary as the existing modules: one responsibility each, never touching another
module's state directly.
