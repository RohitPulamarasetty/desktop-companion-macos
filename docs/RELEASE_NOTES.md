# v0.1.0

The first release of Desktop Companion: a macOS-only pixel companion for your desktop.

## What's in it

- **Companion engine** — one deterministic behavior engine (`PetBrain`): roaming, sitting, dozing, sleeping, waking, looking around, sniffing, barking, zoomies, bed visits, day/night rhythm.
- **Six characters** — Biscuit, Ginger, Smoky, Rusty, Snowy, Mango, each with its own temperament.
- **Personality** — restfulness, roaming, reactivity, chattiness, curiosity, affection, playfulness; each has a causal test.
- **Moods** — happy, calm, curious, sleepy, playful, excited, annoyed. Annoyance comes from click spam or repeated waking, fades on its own and is soothed by a pat.
- **Interaction** — click, double-click (pet + dashboard), rapid clicks, drag (also across displays), right-click menu, cursor awareness.
- **Follow Cursor** — smooth, no teleporting or jitter, respects screen edges, timed or until stopped, with an on-screen "Following" badge.
- **Activities** — Follow Cursor, Come Here, Play, Explore, Hide & Seek, Stay — each with a duration, cooldown and interruption handling.
- **Relationship** — familiarity grows over days (anti-farming), shown on the dashboard.
- **Environment** — a bed the companion visits when sleepy.
- **Dashboard, settings, onboarding** — skippable tour that can be replayed.
- **Data portability** — export/import settings, favorites and days together as JSON.
- **Menu-bar control, global shortcuts (⌃⌥⌘F/H/S/D/P), launch at login.**
- **Performance** — ~30 MB, well under 1 % CPU at idle.
- **Local-first** — no network code, no telemetry, no macOS permissions requested.

## Requirements

macOS 13 or newer; universal (Apple Silicon + Intel).

## Known limitations

- **Not notarized.** The app is ad-hoc signed only; on first launch use System Settings → Privacy & Security → Open Anyway.
- One art source: the six characters are recolors of Pixel Dogs by Benvictus (permission is informal — see `THIRD_PARTY.md`). No sound.
- The dogs have no dedicated "play" animation, so Play uses the gallop/beg clips.
- Multi-display support is covered by tests but was not tried on a second physical display.
- The DMG has a plain window (no custom background): Finder scripting on the build machine wouldn't apply one.
- Hide & Seek "found" and Play's celebration, sleep→wake, and four of the five shortcuts were verified by tests but not by hand.
- Data files from earlier builds may remain in `~/Library/Application Support/DesktopCompanion/`; they are unused.
