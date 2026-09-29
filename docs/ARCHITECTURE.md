# Architecture

macOS-only Swift package (`swift-tools-version 5.9`, macOS 13+). No third-party dependencies.

| Target | Role |
|---|---|
| `Core` | Everything testable without AppKit: `PetBrain`, `Activity`, moods, personality, `InteractionMemory`, settings, SQLite pet state, data export/import, character manifests. |
| `PlatformMac` | AppKit: transparent stage window (`CharacterWindowController`), sprite rendering (Core Animation), menu bar + menu, global hotkeys (Carbon `RegisterEventHotKey`, no permission), settings, dashboard, picker, onboarding. |
| `DesktopCompanionApp` | `AppDelegate` wiring, housekeeping tick (30 s), persistence. |
| `CoreTestsRunner` | Dependency-free test runner (XCTest needs full Xcode). |

## Behavior

`PetBrain` is the only behavior engine. One primary behavior runs at a time; each is a small spec
(clip steps or a movement leg, follow-ups, whether it's "quiet"). `chooseNext` scores options from
posture, energy, boredom, curiosity, affection, personality multipliers, mood, mode, time of day,
cursor position, familiarity and short-term memory, with a repetition penalty.

**Activities** (`Activity`, `PetBrain.startActivity`) never bypass the brain:

- *Follow Cursor / Play* set a follow window; `finish()` then keeps choosing "follow" (moving legs that
  are re-aimed mid-leg at constant speed) or a short watch pause. Ends on stop, timeout, or sleep.
- *Come Here, Explore, Hide & Seek* queue ordinary behaviors and end when the queue drains, with a hard deadline.
- *Stay* suppresses roaming until it expires.
- Each activity declares a default duration, cooldown and the behaviors (art) it needs; a character
  without that art simply doesn't get it (`ActivityAvailability.unsupported`).

**Mood** is derived (sleepy, annoyed, excited, playful, curious, happy, calm). *Annoyed* is a timed
window (120 s) set by click spam or repeated waking; it lowers cursor-seeking and play, favors sulking
away, decays on its own and is soothed by a pat.

**Personality** (restfulness, roaming, reactivity, chattiness, curiosity, affection, playfulness) scales
the same weights; each has a causal test in `MoodAndPersonalityTests`.

## Rendering

Movement legs are pure functions of time (`MovementLeg`); the window hands each leg to Core Animation with
the same bezier the brain uses, so nothing is stepped per frame. Sprite strips are decoded once per clip.

## Storage

`UserDefaults` for settings and progression; one SQLite file (`~/Library/Application Support/DesktopCompanion/pet_state.sqlite`)
for position, energy, daily stats, discovered behaviors and activity counts.
