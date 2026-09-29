# v1.0.0

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
