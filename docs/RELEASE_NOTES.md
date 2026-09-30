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
- **The companion could still walk backward while following a moving cursor, in the real app.** Found by watching real rendered frames: the app ticks about once a second while following, and the follow re-aim step used to discard the whole time step, so the brain stood still (at x=0 for eight seconds in one capture) while the sprite glided across the screen. After the cursor reversed, the brain, thinking it was somewhere else, faced the wrong way. Fixed (the time step is kept), following is polled every 0.3 s, and new tests run a model of the renderer beside the brain at the real tick rate for every command. The unit tests missed it because they ticked faster than the app does.
- **Corgi Scout's walk and run art was swapped as well** (my first review misjudged its three-quarter view; found in the real render and confirmed on full frame strips). All directional packs were re-reviewed by tail/beak/limb cues and are recorded in an art ledger test; the front-facing ones (board, planet, robot, Luna, scissors, lunchbox, owl, mole, cactus, cloud, Astro) can't be judged by eye and cannot visibly walk backward.
- **Menu: Follow Cursor, Come Here, Play and Watch Cursor were greyed out** ("cursor not on this display") even with the mouse on the only display, because the menu's context never received the cursor position. They can now be started from the menu.
- **Characters no longer walk backward.** A leg that was mostly vertical kept the old facing even when it carried the companion a long way sideways; one facing rule now applies to every movement path, including moves interrupted by a drop or a display change. A simulation of roaming reproduced up to 67 pt of backward travel before the fix and none after.
- **Wrong-way art:** the walk and run clips of Azure, Purple and Shadow Kit were labelled the wrong way round in their packs (they showed the character walking backward even with perfect logic); corrected in their manifests. The other packs were checked at zoom; a handful of near-symmetrical front-facing characters (board, lunchbox, planet, scissors) can't visibly walk backward.
- **Messages:** species-specific words removed (there are dragons, cacti and planets among the companions), false claims removed ("it's daytime", "four in a row" with a custom cycle, "Miss me?" from a brand-new companion), a gentler tone for tasks and focus, no meeting-app comments, no duplicate morning greeting plus brief, one wording per reminder (banner and bubble), a shared budget so unprompted chatter is at most every few minutes and rarer at night.
- **Honest saves:** if a task, water glass, break or reminder can't be written, the companion says so instead of celebrating. A corrupt database is set aside (kept as `.corrupt`) and replaced instead of silently disabling the feature.
- Window titles and Settings labels now follow a character switch (they lagged one character behind); the About window credits the OpenPets community as well as Pixel Dogs.
- Character picker memory: only the selected/hovered card holds its animation (about 30–40 MB less while the picker is open).
- **Skipping a focus session no longer banks a full session.** Skip during focus used to record the whole planned length as completed (and celebrate); it now credits only the time really spent (none under 3 minutes) and moves to the break quietly. Found during manual QA.
- Quick Add ambiguity (see above).

## Verification
- 388 automated checks pass (`swift run CoreTestsRunner`; baseline for this release line: 345). New ones cover the facing matrix across all 36 characters, a 20-minute randomized soak per character (all modes, commands and events, character switches, display changes), the message catalog, corrupt-store recovery, braking and settling of Follow Cursor, fast cursor flicks, every activity always ending, a simulated day with character/clip switches and display-size changes, Watch/Nap, focus credit, mood proportionality, character profiles, Quick Add ambiguity and week insights.
- **Manually verified in the installed app, through its own controls** (macOS accessibility actions on the app's windows, one display, macOS 27): Quick Add creating a task (title, time, priority, weekly repeat, 30-minute reminder all stored correctly); completing a repeating task (next occurrence created a week later, completed one listed under Done); Upcoming/Done filters; the task ⋯ menu; Focus start, pause (time held), resume, skip and stop; "I drank water", "Take a break now" and adding a custom reminder in Wellness; Stats charts and insights; the Today and Dashboard windows; quit and relaunch keeping data.
- The new icon was confirmed through the system icon service on the built `.app` and the DMG copy; the menu-bar glyph was judged from renders at menu-bar size on light and dark bars.
- Measured on the installed app (one display, screen locked while measuring, so window redraw cost may be understated): ~0.3 % CPU idle, ~0.4 % following the cursor, ~1 % with the Stats window open, ~3 % during 60 rapid character switches; memory ~45–55 MB idle, ~80 MB with the productivity window, ~85–98 MB while the character picker and dashboard are open (was ~115–150 MB), back to ~44 MB after 60 switches.
- **Also manually verified in the installed app (second session):** the character picker (all cards, only the selected one animating), a character's detail page, the About window, five real character switches through the picker (each persisted), 12 Settings checkboxes plus the Talkativeness popup.
- **Manually verified in the installed app (third session):**
  - Real rendered frames of Follow Cursor with a scripted cursor path (a QA-only hook feeds the brain a synthetic cursor; the real pointer is never touched) for Azure, Corgi, Biscuit (mirrored art), Purple, Shadow Kit and Penguin: correct facing on every leg and every reversal.
  - Activities observed frame by frame with a trace of what the brain and renderer each believe: Follow, Explore, Watch, Nap (with its wake-up line), Play, Come Here, Stay, Hide & Seek, Sleep. No backward walking, no brain/sprite disagreement, stable foot line.
  - Follow Cursor and Stop Activity started from the real menu, the companion running to the real mouse position and stopping beside it.
  - The onboarding tour, all six pages through its real buttons.
  - Settings: Display, Interaction, Environment, Privacy controls changed, quit, relaunched and all persisted, then restored.
  - Tasks: Rename (through the alert), Duplicate, Delete, priority cycle, "Tomorrow morning" reschedule.
  - Focus Skip no longer records a session.
  - The Settings title now follows character switches.
- **Not manually verified:** the reminder bubble's Done/Snooze/Dismiss buttons (drawn on the companion, not exposed to accessibility, and I do not click by screen coordinates), morning brief and recap, eye/stretch/bedtime prompts, global shortcut key presses, macOS notification banners, the menu-bar item itself (its menu was opened through the app's own hook), Launch at Login (a system setting, deliberately not toggled), VoiceOver, live viewing of the activities by a person, and everything involving a second display.

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
