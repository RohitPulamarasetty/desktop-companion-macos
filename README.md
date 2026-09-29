<div align="center">

# 🐾 Desktop Companion

**A beautiful little companion that lives on your Mac.**

A tiny companion that wanders your desktop, naps when it's tired, notices your cursor,
follows you around, does tricks, plays hide & seek, talks to you — and slowly gets to know you.

<img src="docs/images/picker.png" width="520" alt="Choosing a companion">

</div>

## ✨ Features

- **Alive, not random** — one behavior engine with moods, energy, drives and cooldowns: it roams, sits, dozes, sleeps, wakes up, gets curious, gets bored, gets excited and sometimes gets annoyed.
- **Follow Cursor** — smooth, never teleports, respects screen edges, stops when you say so.
- **Activities** — Follow Cursor · Come Here · Play · Explore · Hide & Seek · Stay.
- **36 companions with their own temperaments** — pixel dogs, a fox, a dragon, a robot, a penguin, a cactus… each behaves differently (playfulness, curiosity, energy, affection…).
- **It talks** — hundreds of little lines: reactions to clicks and pats, mood and time-of-day chatter, comments when you pick it up, put it down or walk by. Adjustable in Settings → Talkativeness.
- **Tricks & hearts** — ask it to Sit, Lie Down, Beg, Speak or Spin from the menu (only the tricks its art can do); double-click for a pat and floating hearts.
- **It gets to know you** — familiarity grows over days (not by click-spamming), and shows in how often it approaches and how it greets you.
- **Dashboard, settings, onboarding** — mood, current activity, days together, favorite activity, milestones.
- **Tiny and local** — ~30 MB of memory, well under 1% CPU at idle, no network code at all.

## 🖥️ macOS

**macOS only.** macOS 13 (Ventura) or newer, Apple Silicon and Intel (universal app).

## 🚀 Installation

1. Download `DesktopCompanion-v0.1.0-macOS.dmg` from the [Releases](../../releases) page.
2. Open it.
3. Drag **Desktop Companion** onto **Applications**.
4. Open it from Applications.

That's it — no Terminal, no setup.

> **First launch:** the app isn't notarized by Apple (that needs a paid developer account), so macOS will
> say it can't verify it. Open **System Settings → Privacy & Security**, scroll down and click
> **Open Anyway**. You only do this once.

## 🎮 Interactions

| Do this | Get this |
|---|---|
| Click | It looks at you (or wakes up, or barks) |
| Double-click | A pat, with hearts ❤️ and a happy line |
| Click a lot | It gets excited, then annoyed. Give it a minute (a gentle pat helps) |
| Drag | Carry it anywhere, even to another display |
| Right-click / menu-bar 🐾 | Activities, tricks, dashboard, mode, companions, settings |
| **⌃⌥⌘F** | Follow the cursor on/off |
| **⌃⌥⌘H** | Come here |
| **⌃⌥⌘S** | Stop the current activity |
| **⌃⌥⌘D** / **⌃⌥⌘P** | Dashboard / show or hide the companion |

Hide & Seek: it runs to a far corner and crouches. Move your cursor near it — or click it — to find it.

## 🧠 How it works

A single deterministic engine, `PetBrain`, picks what the companion does next from weighted options
(energy, boredom, curiosity, affection, personality, mood, time of day, cursor, cooldowns). Activities
are queued behaviors and timed windows inside that same engine — there is no second brain, and no AI
model. Movement is planned as eased legs and handed to Core Animation, so the app does almost no work
per frame.

## 🔒 Privacy

Everything stays on your Mac. There is **no network code**, no analytics, and no account. The app asks
for **no macOS permissions**: it doesn't use accessibility, screen recording, notifications, camera or
microphone. It reads only how long it's been since your last keypress or click (to know if you're around)
and, if you turn on "step aside" options, the name of the frontmost app. Settings → Privacy lists what is stored.

## 🛠️ Development

```bash
swift build                      # debug build
swift run CoreTestsRunner        # the test suite (no Xcode needed)
./scripts/package_app.sh         # universal, ad-hoc signed release/Desktop Companion.app
./scripts/package_dmg.sh         # release/DesktopCompanion-v0.1.0-macOS.dmg
```

Layout: `Sources/Core` (engine, no AppKit) · `Sources/Platform/macOS` (windows, menus, UI) ·
`Sources/App` (wiring) · `Sources/CoreTestsRunner` (tests) · `Characters/` (art packs) · `docs/`.

## 📜 License

The code is [MIT](LICENSE) © Rohit Kumar Pulamarasetty.

The companion artwork is **not** covered by that license. The six pixel dogs are derived from
[Pixel Dogs by Benvictus](https://benvictus.itch.io/pixel-dogs); the other 30 companions come from the
OpenPets catalog. Sources, credits and caveats are in [THIRD_PARTY.md](THIRD_PARTY.md).
