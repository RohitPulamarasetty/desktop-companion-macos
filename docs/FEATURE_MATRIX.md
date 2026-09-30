# Feature matrix — v1.1.0

"Automated" = covered by `swift run CoreTestsRunner` (366 tests). "Manual" = done by hand against the
installed app (`/Applications/Desktop Companion.app`, copied out of the final DMG) on one Mac
(macOS 27, Apple Silicon, one display). Nothing is marked verified unless it was.

| Feature | Implemented | Automated test | Manual test | Result |
|---|:-:|:-:|:-:|---|
| Character rendering | ✅ | every clip of every character resolves, sprite strips match manifests | picker/dashboard/pet screenshots | Verified |
| Tricks & hearts | ✅ | every trick runs / is hidden without art, wakes a sleeper | menu shows Tricks for the fox; hearts not captured in a screenshot | Partly manual |
| Messages | ✅ | every category ≥4 lines, no back-to-back repeats, ≥12 click/idle lines | bubble seen on screen | Partly manual |
| Click while walking | ✅ (bug fixed) | brain stops moving and drops its leg | in-app click hook: pet froze in place, no sliding | Verified |
| Character switching | ✅ | brain state survives a switch | 60 rapid switches across all 36 characters via the QA hook, footprint 17 → 28 MB and flat | Verified |
| Follow Cursor | ✅ | walks to cursor, tracks a moving cursor without jumps, no jitter, edge/offscreen cursors, timed end, stop, drag-resume | pet converged beside the cursor; "Following" badge; CPU ≈ 0.05 % | Verified |
| Come Here | ✅ | arrives near cursor, ends | pet walked toward the cursor | Verified |
| Stay | ✅ | holds position, expires | position held for 20 s | Verified |
| Play | ✅ | catches → celebration, timeout | chase started and followed the cursor; the celebration ending was only checked in tests | Partly manual |
| Explore | ✅ | covers ground, ends | pet roamed to new areas | Verified |
| Hide & Seek | ✅ | hides far from cursor, found by cursor or click, gives up | pet ran to a far corner and crouched; "found" was only checked in tests | Partly manual |
| Sleep / wake | ✅ | sleep, wake, wake-ups, grumpy wake | sleep command lay the pet down; wake wasn't checked by hand | Partly manual |
| Mood (incl. annoyed) | ✅ | reachable, decays, soothed by pat, bounded | dashboard shows mood | Unit-tested |
| Personality | ✅ | causal tests: playfulness, curiosity, restfulness, affection, reactivity, energy | — | Unit-tested |
| Familiarity | ✅ | bounded, anti-farming (days, not clicks) | dashboard label + bar | Verified |
| Memory | ✅ | fields set/bounded; neglect and recent naps change choices | — | Unit-tested |
| Dashboard | ✅ | — | screenshots, live values change | Verified |
| Settings | ✅ | store/round-trip tests | Companion tab inspected; other tabs not clicked through one by one | Partly manual |
| Favorites | ✅ | filter + persistence | — | Unit-tested |
| Environment (bed) | ✅ | goes to bed when sleepy, suppressed while following | not observed by hand | Unit-tested |
| Import / export | ✅ | round-trip, malformed/out-of-range rejected untouched | file panels not exercised by hand | Unit-tested |
| Onboarding | ✅ | progress store | skip, full walk-through, not shown again after relaunch | Verified |
| Persistence | ✅ | restart-persistence tests | character + energy + onboarding survived quit/relaunch | Verified |
| Quit / relaunch | ✅ | — | AppleScript quit, relaunch from /Applications | Verified |
| Launch at login | ✅ | — | registered and unregistered (checked in the system login-items database) | Verified |
| Global shortcuts | ✅ | — | ⌃⌥⌘F started following; the other four not pressed | Partly manual |
| Tasks (quick add, dates/times, priority, repeat, reminders) | ✅ | parser (dates, times, priority, repeat, reminder), recurrence, planner stages, stores | quick-add created a task in the real database; task list and filters rendered | Partly manual |
| Task reminders (Done / Snooze / Dismiss) | ✅ | queue rules (quiet hours, focus, away), planner | reminder bubble with buttons shown on screen; the buttons themselves were **not** clicked (session locked) | Partly manual |
| Pomodoro focus | ✅ | plan, cycle dots, timer, history (stopped-early counts) | 1-minute cycle ran: timer badge → 🎉 → break timer | Verified |
| Water, screen-break, eye, stretch, bedtime nudges | ✅ | nudge schedule, reminder kinds, settings | water card + wellness screen shown; nudge prompts not waited for | Unit-tested |
| Productivity window (Today/Tasks/Focus/Wellness/Stats) | ✅ | — | all five tabs rendered with real data | Verified (visually) |
| Stats & streaks | ✅ | streak calculator | 7-day charts rendered from real history | Verified (visually) |
| Morning brief / recap | ✅ | — | not triggered by hand | Not verified |
| App-aware comments | ✅ (opt-in) | categoriser, messages | not triggered by hand | Unit-tested |
| Watch Cursor / Nap / Celebrate trick | ✅ | stays put and faces the cursor, ends, cooldown; nap restores energy, early wake, no roaming; every character supports both | not run by hand (session locked) | Unit-tested |
| Quick Add ambiguity ("at 5", impossible dates, warnings) | ✅ | new parser tests | preview text not seen on screen | Unit-tested |
| App icon / branding | ✅ | — | built `.app` icon resolved through the system icon service; About/onboarding render the same icon (not seen on screen) | Partly manual |
| Reliability | ✅ | random command storms (1 h simulated × 6 seeds), missing art, tiny/huge screens, 24 h simulations | — | Verified |
| Multi-display | ✅ | placement tests (per-display bounds, disconnect fallback) | **not** tested with a second display | Unit-tested |
| DMG install | ✅ | — | mount → drag to Applications → launch → quit → relaunch | Verified |

## Performance (installed app, one display)

| Measure | Result |
|---|---|
| Startup | ~55 MB RSS, 14 MB footprint, ~0.2 s CPU time in the first 3 s |
| Idle (roaming), steady state | 0.3–0.5 % CPU, ~30 MB footprint |
| First minute after launch | ~3.7 % CPU (decoding sprites, intro walk) |
| Follow Cursor (chasing a moving cursor) | ~0.05–0.1 % CPU |
| 60 character switches in 17 s | 2.4 % CPU, footprint unchanged |
| Long run | see the release notes |

## Added in this release line

| Feature | Automated | Manual (installed app) | Result |
|---|---|---|---|
| Follow Cursor braking, settling, fast flicks | slows into the stop after a chase, no oscillation once settled, bounded jumps | not re-observed on screen | Unit-tested |
| Character detail: temperament + abilities | neutral = nothing, top-3 strongest, abilities only from real art, every shipped character | not opened on screen | Unit-tested |
| Task Rename / Duplicate | — | not exercised (session locked) | Unverified |
| Focus skip credit | credit = time spent, none under 3 min, capped at plan | Skip/Stop seen working; the fix itself not re-run in the app | Unit-tested |
| Quick Add → task (real Add button) | parser tests | created with correct time, priority, weekly repeat, reminder | Verified |
| Complete repeating task | store tests | next occurrence a week later; Done list | Verified |
| Focus start / pause / resume / skip / stop | timer tests | driven through the window's buttons | Verified |
| Water / break / custom reminder (Wellness) | store/nudge tests | driven through the window's buttons | Verified |
| Stats + insights, Dashboard weekly row | insight tests | Stats rendered with live data; Dashboard row not seen | Partly manual |
| Notifications: stable ids, withdrawn on handling | queue tests | not observable without system banners | Unverified |
| Global shortcut conflict notice | — | not exercised | Unverified |
| Settings controls | store tests | not clicked (session locked) | Unverified |
| Character picker / detail, multi-display | placement/character tests | not seen | Unverified |
| Long-run | simulated day with clip switches and display resizes, every activity ends, 6 × 1 h command storms | 150 s of 60 character switches: memory back to baseline | Verified |
