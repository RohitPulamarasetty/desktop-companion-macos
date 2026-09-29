# Feature matrix — v0.1.0

"Automated" = covered by `swift run CoreTestsRunner` (257 tests). "Manual" = done by hand against the
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
