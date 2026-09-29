# Desktop Companion

A desktop pet / companion app for macOS: a small animated character lives
on your desktop, reacts to your mouse, keeps you company while you work,
and doubles as a lightweight productivity dashboard (focus timer,
reminders, tasks, a simple wellness log).

**Status: v0.1.0, free, non-commercial, open-source testing release.**
Not notarized, not code-signed with a real Developer ID, and not all of
it has been manually verified through the GUI — see
[Honest status](#honest-status) below before relying on any claim here.

## Features (verified this session against source and a real local test run)

- **6 companion modes** (`normal, quiet, focus, play, sleep, attention`)
  and **13 real commands** (`sleep, wake, comeHere, play, quiet, stop,
  follow, stay, playChase, startFocus, stopFocus, setReminder,
  startTimer`) — see `Sources/Core/Behavior/PetMode.swift` /
  `PetCommand.swift`.
- **Personality system**: restfulness/roaming/reactivity/chattiness/
  curiosity/affection dials that measurably change behavior selection.
- **Structured short-term memory**: last click/command/play/sleep,
  approach cooldowns, play-drought weighting, bounded growth (never grows
  unbounded — covered by `InteractionMemoryTests.swift`).
- **Relationship/familiarity**: a `daysTogether`/`activeDayCount`-based
  model that gradually increases approach frequency and boredom relief,
  bounded and personality-modulated, with an explicit anti-farming design
  (active days, not raw click count).
- **Environment object**: a bed the pet can approach and use, wired via a
  generic, reusable `EnvironmentObject` discovery mechanism.
- **31 character packages**, each with a full sprite/animation set,
  personality, and license metadata — see
  [Character asset licensing](#character-asset-licensing) for which ones
  ship with playable art by default.
- **A cursor-chase mini-game**, click-through desktop overlay window,
  drag/drop physics (with fall/land), menu-bar control, a character
  picker with favorites, a 7-tab settings window, and a 5-section
  productivity dashboard (today / tasks / focus / wellness / pet).
- **Desktop awareness**: idle-time detection, battery state, fullscreen/
  activity tracking — all event-driven, no busy-polling loops.
- **Character pack lifecycle** (installed/enabled/disabled/removed/invalid)
  so a missing or invalid optional character pack never crashes the app.
- **Local data export/import**: settings, character selection, favorites,
  and relationship/progression data can be exported to and restored from a
  local file — no account or network required.
- **First-launch onboarding**: a skippable, persisted tour explaining
  interaction, the menu, commands, character switching, settings, and
  privacy.
- **Formal `Platform*` protocol seams** (`Sources/Core/Platform/PlatformProtocols.swift`)
  naming the interface a second shell implements — see
  `docs/PLATFORM_PROTOCOLS.md`.
- **1335/1335 automated tests passing** (`./.build/debug/CoreTestsRunner`,
  re-run and confirmed in this session on a clean build).

## Supported platforms — build vs. runtime-verified, honestly

| Platform | Build | Full app runtime |
|---|---|---|
| macOS 13+ (Apple Silicon & Intel) | Verified — full app builds and the packaged `.app`/`.dmg` launch-smoke-tests cleanly | Partially verified — core behavior is covered by 1335 automated tests, including 958 exhaustive per-character validation tests; **GUI interaction (settings tabs, character picker, dashboard, full bed lifecycle) is largely manually unverified**, see `docs/FINAL_PRODUCT_AUDIT.md` §3/§10 |
| Linux | **Build verified** against a real Linux Swift 5.9.2 toolchain (Docker/colima): `Core`, `CoreTestsRunner`, and a real SDL2 GUI shell (`Sources/PlatformLinux`) all compile cleanly | **Runtime verified (headless) and packaged**: the SDL2 shell creates a real window, loads and renders a character's actual sprite frames under Xvfb, and responds to injected mouse input through the same `PetBrain.handle(_:context:)` entry point the macOS shell uses — see `docs/LINUX_CLIENT_STATUS.md`. **Packaged** as a real `.AppImage` (plus a bonus `.deb`), aarch64 only — no x86_64 build |
| Windows | Source written (`Sources/PlatformWindows`) conforming to the `Platform*` protocols, using Win32/GDI+ APIs — **never compiled or run**, no Windows machine or toolchain available this session | Not applicable — completely unverified. Known, explicitly-flagged bugs in the code (a dangling pointer in window-class registration, a sprite-loader row-math bug) — see `docs/WINDOWS_CLIENT_STATUS.md` for the full list |

The full macOS app (`DesktopCompanionApp`, `PlatformMac`, `Diagnostics`
targets) is AppKit-based and macOS-only by design; `Sources/Core` alone is
platform-neutral Swift with zero AppKit/Darwin dependencies, which is the
engine boundary the Linux SDL2 shell and the (unverified) Windows shell
both build against — see `docs/PLATFORM_PROTOCOLS.md`.

## Install / build / test

Requires Swift 5.9+ (Xcode Command Line Tools are sufficient; full Xcode
is not required to build or test).

```bash
git clone <this-repo>
cd desktop-companion

# Build (debug)
swift build

# Run the full Core test suite (1335 tests)
swift build
./.build/debug/CoreTestsRunner

# Build + run the macOS app directly (debug)
swift build
.build/debug/DesktopCompanionApp

# Package a real .app bundle (release build, verified structure,
# launch-smoke-tested)
./scripts/package_app.sh

# Build a .dmg from the packaged .app (unsigned, unnotarized — see
# docs/RELEASE_CHECKLIST.md)
./scripts/package_dmg.sh
```

The packaged `.app`/`.dmg` ship with only 1 of the 31 characters'
sprite/sound assets by default (`biscuit-proto`) — see below. Running
directly from `swift build`/`.build/debug/DesktopCompanionApp` reads
`Characters/` from the working tree, so all 31 characters' assets are
available there for local development regardless.

## Architecture summary

- **`Sources/Core`** — platform-neutral Swift engine: `PetBrain` (behavior
  selection over ~66 `PetBehavior` cases, personality/mood/memory-weighted),
  character package loading/validation (`CharacterPackageLoader`,
  `ManifestValidator`, `PackagePathPolicy` — content-policy allow-listed,
  path-traversal-safe), progression/relationship persistence
  (`ProgressionStore`), productivity stores (`FocusTimer`, `ReminderEngine`,
  `TaskStore`, `WellnessLog`), all backed by `SQLiteDatabase.swift`. Zero
  AppKit/Darwin imports — this is the reusable engine seam.
- **`Sources/Platform/macOS`** — the AppKit shell: transparent click-through
  desktop window (`CharacterWindowController`, `TransparentPanel`), menu bar
  controller, settings/character-picker/dashboard UI (hand-built AppKit, no
  SwiftUI), idle/battery/fullscreen readers, notification scheduling.
- **`Sources/App`** — `AppDelegate`, `Info.plist`, app entry point, and app
  icon.
- **`Sources/Diagnostics`** — a runtime performance sampler (macOS-only).
- **`Sources/CoreTestsRunner`** — a custom, dependency-free `MiniTest`
  harness (no XCTest dependency, so `Core` stays testable on non-Apple
  platforms too) running all 1335 tests.
- **`Sources/PlatformLinux`** — a minimal SDL2 GUI shell for Linux, build-
  and runtime-verified this session (headless, via Xvfb) — see
  `docs/LINUX_CLIENT_STATUS.md`.
- **`Sources/PlatformWindows`** — a Win32/GDI+ shell for Windows, written
  and reviewed but never compiled or run (no Windows environment
  available) — see `docs/WINDOWS_CLIENT_STATUS.md`.
- **`Characters/<id>/`** — one directory per character package
  (`manifest.json` + `sprites/` + optional `sounds/`/`preview.png`/
  `source/`) — see `docs/CHARACTER_PACKAGES.md` for the full format.
- **`scripts/`** — Python build tooling (`build_characters.py`,
  `build_petpack.py`) and bash packaging/release tooling
  (`package_app.sh`, `package_dmg.sh`, `prepare_public_repo.sh`).

See `docs/ARCHITECTURE.md`, `docs/CROSS_PLATFORM_ARCHITECTURE.md`, and
`docs/FINAL_PRODUCT_AUDIT.md` for much more detail, including what's
explicitly *not* implemented yet.

## Character asset licensing

**Read `docs/CHARACTER_LICENSING.md` before assuming any character's art
is freely redistributable.** Short version: of the 31 character packages,
**zero** currently have an explicit, confirmed grant of both commercial
use *and* redistribution rights. One character (`biscuit-proto`) has a
real, named, on-file grant of commercial *use* from its actual author and
ships with playable sprites by default in the packaged app/dmg as a
documented, calculated risk for this free testing release. The other 30
characters' manifests (metadata, personality, code paths, tests) ship and
work, but their sprite/sound/preview assets are **not** included in the
default packaged app — see that document for exactly why, the precise
per-character breakdown, and how to legally source those assets yourself
if you already have rights to them.

## Contributing

See `CONTRIBUTING.md` for how to build, test, add a character or
behavior, and what a good PR looks like.

## Security

See `SECURITY.md` for how to report a vulnerability.

## License

Engine and application code: MIT — see `LICENSE`. Character assets are
licensed separately and individually; see
[Character asset licensing](#character-asset-licensing) above and
`docs/CHARACTER_LICENSING.md`.

## Honest status

This is a v0.1.0 testing release, not a finished commercial product. In
particular, as of this milestone: CI workflows exist for macOS
(`.github/workflows/macos.yml`), Linux (Core + the SDL2 shell), and
Windows Core builds, but GitHub Actions is billing-blocked for this
account, so none of them have actually had a real recorded run even after
this milestone's push to `origin/main` — the 1335/1335 pass count is a
real, just-re-run local fact, not yet a CI-gated one; the app is not
code-signed with a real Developer ID or notarized (Gatekeeper will warn
on other machines); the app icon is a placeholder glyph, not designed
brand art; and most GUI-level interaction has not been manually QA'd. The
Linux SDL2 shell is real, build- and runtime-verified (headlessly), and
packaged as a real `.AppImage`/`.deb` (aarch64 only); the Windows shell
is source-only — its two previously-known bugs are fixed at the source
level, but it remains completely unverified (never compiled), with no
Windows environment available anywhere — see `docs/LINUX_CLIENT_STATUS.md`
and `docs/WINDOWS_CLIENT_STATUS.md`. `docs/FINAL_PRODUCT_REPORT.md` is the
authoritative, source-verified account of what's actually implemented vs.
claimed, and `docs/FINAL_RELEASE_CHECKLIST.md` tracks exactly what's left
before a real signed/notarized release.
