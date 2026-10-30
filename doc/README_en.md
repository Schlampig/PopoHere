# PopoHere

> Turn a real cat into a cat that lives on your desktop.

PopoHere is a desktop pet for macOS. No Dock icon, no focus stealing — it just sits on your screen, breathing, wandering around, falling asleep, and flailing its legs when you pick it up.

The original model is a British Shorthair named **Popo**. **You can swap in your own pet** — all it takes is a few photos.

<p align="center">
  <img src="../code/pet_images/landed.png" width="240" alt="Popo">
</p>

---

## What makes it different

- **Native, yet tiny** — an Objective-C shell plus a WebView. The whole bundle is 768KB, launches in under half a second, and has **zero third-party dependencies**
- **No network** — not a single line of networking code, no file access, everything runs locally
- **Universal binary** — runs on both Intel and Apple Silicon
- **State-machine driven** — idle, playing, sleeping, being petted, startled, carried. States flow by probability, the way a cat actually behaves, instead of looping one animation forever
- **Drag that actually tracks** — window movement is driven by the native layer using screen coordinates, not by JS messages chasing the cursor (there is a real trap here — see [ARCHITECTURE.md](ARCHITECTURE.md))
- **Swap in your own pet** — drop photos into `source/origin_images/`, run one command, rebuild

---

## Install

**Requires** macOS 11 (Big Sur) or later.

1. Download the latest zip from [Releases](../../releases)
2. Unzip and drag `PopoHere.app` into `/Applications`
3. Double-click to launch

Since this is a personal project without a paid Apple Developer certificate, **macOS will block the first launch**:

> "PopoHere" cannot be opened because the developer cannot be verified.

This is not malware. **Right-click** (or Control-click) the app icon → **Open** → **Open** again. **Once only**, then it works normally forever.

Or just run:

```bash
xattr -dr com.apple.quarantine /Applications/PopoHere.app
```

---

## How to play with it

| Action | Reaction |
|---|---|
| Click and drag | Pick it up, carry it around. It lands on its own when you let go |
| Click upper body | Pet the head |
| Click lower body | Touch the paws; do it repeatedly and it gets annoyed and scratches |
| Poke it while asleep | Startled awake |
| Do nothing | After 5 seconds it wanders off or lies down to sleep |
| Right-click | Menu: show/hide, pause, size, quit |

Position and size are remembered between launches.

---

## Make your own

No coding required.

**Step 1: photos.** Shoot 6–12 photos of your pet, ideally from the same angle under similar light. Put them in `source/origin_images/`, named by state:

```
source/origin_images/
├── idle.png           at rest
├── idle_2.png         add an index to give a state several frames; one is picked at random
├── sleep.png          sleeping
├── touch_1.png    being petted
├── touch_2.png
├── walk.png           wandering
├── dragging.png       picked up
└── ...
```

**Keep the background a solid colour** (a plain wall, a plain floor). Background removal is semantic segmentation, not a large model — solid backdrops give the cleanest edges. The full state list and naming rules are in the [PRD](PRD/PRD.md).

**Step 2: preprocess.**

```bash
pip install pillow rembg      # only these two
python3 code/prepare/cutout.py
```

It cuts the background out, normalizes to a shared canvas, aligns to a ground baseline, and writes to `code/pet_images/`.

**Step 3: rebuild.**

```bash
./code/build/build_app.sh --run
```

Done. `code/build/dist/PopoHere.app` is your own desktop pet.

---

## Project layout

```
PopoHere/
├── source/                 your raw assets (images / audio)
├── code/
│   ├── prepare/            raw photos → usable sprites
│   ├── pet_images/         processed sprites + theme.json (state ↔ sprite contract)
│   ├── pet_audios/
│   ├── pet_others/         app icon, menu-bar logo
│   ├── core/               the pet itself (style-agnostic)
│   │   ├── func_state/       state machine (pure logic, no DOM)
│   │   ├── func_render/      state → sprite / motion
│   │   ├── func_input/       hit testing, click vs drag
│   │   ├── func_menu/        context menu
│   │   └── func_window/      AppKit shell (window / menu bar / JS bridge)
│   ├── build/              build & packaging scripts
│   ├── test/               tests
│   └── prototype/          HTML shell template
├── doc/                    PRD, architecture notes, guides
├── README.md
└── AGENTS.md
```

---

## Development

```bash
# preview in a browser (with a debug panel)
python3 code/build/build_web.py
open code/build/out/preview.html

# tests: 32 state-machine assertions + 7 drag assertions
node code/test/state_machine_test.js
python3 code/test/drag_tracking_test.py

# build the app
./code/build/build_app.sh

# package a release zip
python3 code/build/package_release.py
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for design decisions and traps. Contributors should read [AGENTS.md](../AGENTS.md) first.

---

## License

[MIT](../LICENSE)
