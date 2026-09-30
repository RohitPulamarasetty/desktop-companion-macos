# v1.1.0

A new identity, new activities, a smoother Follow Cursor, a sharper Quick Add and a focus-credit fix. Still 100 % local.

## Branding
- New app icon built from the project's master logo (`Branding/logo.png`), replacing the old Biscuit-on-a-tile icon everywhere: Finder/Applications/DMG, the About window and the first page of onboarding.
- The menu bar shows a small one-colour pup-head glyph (macOS tints it for light/dark), replacing the system paw.
- `scripts/build_icon.py` now regenerates the icon set and menu-bar glyph from the master logo.

## New
- **Watch Cursor** — the companion sits still and keeps its eyes on your cursor for a while.
- **Nap** — a short rest; a finished nap leaves it a bit more energetic, a click wakes it early (no bonus).
- **Celebrate** trick (for characters that can gallop).
- Stats: a few plain observations under the 7-day summary (best focus day, days the goal was reached, average on focus days, busiest task day).

## Quick Add
- "at 5" now means 5 pm (1–6 read as afternoon, 7–11 as morning, 12 as noon); an explicit `am`/`pm` or 24-hour time is always respected.
- Impossible dates (`2026-13-45`, `feb 30`) stay in the title instead of being silently dropped.
- The preview warns when a reminder was ignored (no date) or the time has already passed.
- Adding a task with only a date and no title now asks for a title instead of doing nothing.

## Also new since 1.0
- **Follow Cursor** now decelerates into its stop (a braking curve shared by the brain and the renderer) instead of halting at full speed after chasing a moving cursor.
- **Character detail** shows plain-language temperament lines (only for traits that really differ) and what the character can actually do, derived from its personality and art.
- **Tasks:** Rename and Duplicate in a task's ⋯ menu.
- **Mood:** excitement after a productivity event is proportional (a reminder none, water/one task brief, a finished focus session or a cleared list longer) and always fades.
- **Dashboard:** a "Last 7 days" row.
- **Notifications:** a banner is keyed to what it announces (no stacking), is withdrawn when you handle it in the app, and ticking a task off in the window withdraws the companion's open question about it.
- **Shortcuts:** if another app already owns one of the global shortcuts, Settings → Interaction says which.
- **Privacy:** the optional "comment when I switch kinds of app" setting moved to Settings → Privacy with a more exact description (it reads only the frontmost app's identifier, sorts it into a broad kind and forgets it; off by default).
- **Accessibility:** labelled text fields, chart summaries, familiarity meter and portraits for VoiceOver; visible keyboard focus rings in the productivity window.

## Fixed
- **Skipping a focus session no longer banks a full session.** Skip during focus used to record the whole planned length as completed (and celebrate); it now credits only the time really spent (none under 3 minutes) and moves to the break quietly. Found during manual QA.
- Quick Add ambiguity (see above).

## Verification
- 366 automated checks pass (`swift run CoreTestsRunner`; baseline for this release line: 345). New ones cover braking and settling of Follow Cursor, fast cursor flicks, every activity always ending, a simulated day with character/clip switches and display-size changes, Watch/Nap, focus credit, mood proportionality, character profiles, Quick Add ambiguity and week insights.
- **Manually verified in the installed app, through its own controls** (macOS accessibility actions on the app's windows, one display, macOS 27): Quick Add creating a task (title, time, priority, weekly repeat, 30-minute reminder all stored correctly); completing a repeating task (next occurrence created a week later, completed one listed under Done); Upcoming/Done filters; the task ⋯ menu; Focus start, pause (time held), resume, skip and stop; "I drank water", "Take a break now" and adding a custom reminder in Wellness; Stats charts and insights; the Today and Dashboard windows; quit and relaunch keeping data.
- The new icon was confirmed through the system icon service on the built `.app` and the DMG copy; the menu-bar glyph was judged from renders at menu-bar size on light and dark bars.
- Measured on the installed app (one display, screen locked while measuring, so window redraw cost may be understated): ~0.3 % CPU idle, ~0.4 % following the cursor, ~1 % with the Stats window open, ~3 % during 60 rapid character switches; memory ~45–55 MB idle, ~80 MB with the productivity window, ~115–150 MB while the character picker is open, back to ~44 MB after 60 switches.
- **Not manually verified** (the desktop session locked partway through; nothing was unlocked or bypassed): every Settings control, the character picker and detail pages, task Rename/Duplicate and the Skip fix in the running app (covered by unit tests only), the reminder bubble buttons (Done/Snooze/Dismiss), morning brief and recap, eye/stretch/bedtime nudge prompts, global shortcut key presses, the menu-bar glyph and About/onboarding pages on screen, and everything involving a second display. The app has no Dock icon by design (menu-bar accessory), so a Dock icon check does not apply.

## Known limitations
- **Not notarized.** Use System Settings → Privacy & Security → Open Anyway on first launch.
- Tasks are a simple list (no projects/tags/subtasks); tasks and history are not part of the JSON export.
- Art licensing: see `THIRD_PARTY.md`.
- No sound; the DMG window is plain.

---

## Earlier: v1.0.0

Desktop Companion grows up: a living companion **and** a productivity assistant, still 100 % local.

## New in 1.0

**Tasks & reminders**
- Add tasks in plain words: `call mom tomorrow 5pm !high every week remind 30m before`.
- Due dates and times, priorities, repeats (daily, weekdays, weekly, monthly), reminders before the deadline, "nudge until done", default reminder lead time.
- Filters: open, overdue, upcoming, done. Snooze or reschedule (1 hour, this evening, tomorrow, next week), change priority, delete.
- Custom reminders with a date-time picker and repeats.
- Reminders arrive as your companion walking over and asking — Done · Snooze · Dismiss — respecting quiet hours, focus and when you're away. Optional macOS notification banners.

**Focus**
- Pomodoro: Classic 25·5, Deep 50·10, Quick 15·3 or your own plan; a long break after each cycle; optional auto-start; live timer badge on the companion; the companion settles down beside you.
- Stopped-early sessions still count toward the day's focus minutes; a daily focus goal.

**Wellness**
- Water goal with reminders; screen-break nudges driven by real activity; 20-20-20 eye breaks; stretch/posture nudges; a bedtime reminder that offers to move open tasks to tomorrow.
- Screen-time totals (active vs idle).

**Insight**
- Today view with goals, next event and streak; Stats view with 7-day charts (tasks, focus, water, screen time).
- Morning brief and evening recap.

**Companion**
- 36 companions, many more messages (tasks, focus, water, moods, time of day, pick-up/put-down), tricks, hearts on a pat.
- Optional "comment on what I'm doing" (frontmost app's name only, off by default).
- Double-click is a pat now; the dashboard is in the menu or on ⌃⌥⌘D.
- Fixed: clicking a walking companion no longer leaves it sliding in a sitting pose.
- New shortcuts: ⌃⌥⌘T new task, ⌃⌥⌘E start/stop focus, ⌃⌥⌘W log water.

## Kept from 0.1
Activities (Follow Cursor, Come Here, Play, Explore, Hide & Seek, Stay), moods including annoyed, personalities, familiarity, memory, bed, dashboard, onboarding, data export/import, launch at login, menu-bar control.

## Requirements
macOS 13 or newer; universal (Apple Silicon + Intel). No permissions required.

## Known limitations
- **Not notarized.** Use System Settings → Privacy & Security → Open Anyway on first launch.
- Tasks are a simple list (no projects/tags/subtasks); tasks and history are not part of the JSON export (they stay in local SQLite files).
- Art licensing: the six dogs rely on an informal permission (Pixel Dogs by Benvictus) and the 30 OpenPets companions have no verified per-pack license — see `THIRD_PARTY.md`.
- The productivity window's buttons and forms, the reminder buttons, morning brief, recap, nudge prompts and second-display behavior were verified by tests and rendered screenshots but not clicked through by hand (the build machine's session was locked during final QA).
- No sound; the DMG window is plain (no custom background).
