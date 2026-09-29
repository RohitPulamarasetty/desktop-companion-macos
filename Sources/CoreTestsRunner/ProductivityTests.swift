import Foundation
import Core

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}
/// Wednesday 4 March 2026, 10:00 UTC.
private let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 10, minute: 0))!

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func parse(_ s: String) -> ParsedTask { QuickAddParser.parse(s, now: now, calendar: cal) }

func runProductivityTests(_ runner: TestRunner) {
    // MARK: Quick add

    runner.run("QuickAdd.plainTitleStaysAsIs") {
        let p = parse("buy milk")
        try expectEqual(p.title, "buy milk")
        try expectTrue(p.dueDate == nil)
        try expectEqual(p.priority, .medium)
    }

    runner.run("QuickAdd.tomorrowWithTime_andPriority") {
        let p = parse("call mom tomorrow 5pm !high")
        try expectEqual(p.title, "call mom")
        try expectEqual(p.dueDate, at(2026, 3, 5, 17, 0))
        try expectTrue(p.hasDueTime)
        try expectEqual(p.priority, .high)
    }

    runner.run("QuickAdd.weekdayNames_pickTheNextOne_andNextWeekSkipsAWeek") {
        try expectEqual(parse("report friday").dueDate, at(2026, 3, 6))
        try expectEqual(parse("report next friday").dueDate, at(2026, 3, 13))
        try expectEqual(parse("standup monday 9:30").dueDate, at(2026, 3, 9, 9, 30))
        try expectEqual(parse("standup monday 9:30").title, "standup")
    }

    runner.run("QuickAdd.relativeOffsets") {
        let m = parse("stretch in 45 min")
        try expectEqual(m.dueDate, now.addingTimeInterval(45 * 60))
        try expectTrue(m.hasDueTime)
        try expectEqual(m.title, "stretch")
        try expectEqual(parse("review in 2 hours").dueDate, now.addingTimeInterval(7200))
        try expectEqual(parse("dentist in 3 days").dueDate, at(2026, 3, 7))
        try expectEqual(parse("plan in 2 weeks").dueDate, at(2026, 3, 18))
    }

    runner.run("QuickAdd.explicitDates") {
        try expectEqual(parse("taxes 2026-04-15").dueDate, at(2026, 4, 15))
        try expectEqual(parse("party oct 5").dueDate, at(2026, 10, 5))
        try expectEqual(parse("party 5 oct").dueDate, at(2026, 10, 5))
        try expectEqual(parse("anniversary feb 2").dueDate, at(2027, 2, 2), "a date already past this year means next year")
        try expectEqual(parse("taxes 2026-04-15").title, "taxes")
    }

    runner.run("QuickAdd.timeFormats") {
        try expectEqual(parse("lunch today noon").dueDate, at(2026, 3, 4, 12, 0))
        try expectEqual(parse("call today at 17:45").dueDate, at(2026, 3, 4, 17, 45))
        try expectEqual(parse("gym tomorrow 6:15 am").dueDate, at(2026, 3, 5, 6, 15))
        try expectEqual(parse("read tonight").dueDate, at(2026, 3, 4, 20, 0))
        try expectEqual(parse("email tomorrow morning").dueDate, at(2026, 3, 5, 9, 0))
        try expectEqual(parse("12am check").dueDate, at(2026, 3, 5, 0, 0), "a bare time that already passed means tomorrow")
        try expectEqual(parse("pray today 12pm").dueDate, at(2026, 3, 4, 12, 0))
    }

    runner.run("QuickAdd.recurrenceAndReminder") {
        let a = parse("water plants every day 8am")
        try expectEqual(a.recurrence, .daily)
        try expectEqual(a.title, "water plants")
        try expectEqual(parse("standup every weekday 9am").recurrence, .weekdays)
        try expectEqual(parse("rent monthly").recurrence, .monthly)
        let w = parse("team sync every monday 10am")
        try expectEqual(w.recurrence, .weekly)
        try expectEqual(w.dueDate, at(2026, 3, 9, 10, 0))
        let r = parse("flight friday 8pm remind 1 day before")
        try expectEqual(r.remindBeforeMinutes, 1440)
        try expectEqual(r.title, "flight")
        try expectEqual(parse("pay bill tomorrow remind 30m before").remindBeforeMinutes, 30)
        try expectTrue(parse("no date remind 30m before").remindBeforeMinutes == nil, "a reminder needs a due date")
    }

    runner.run("QuickAdd.unknownWordsStayInTheTitle_andPriorityVariants") {
        try expectEqual(parse("finish monday-report").title, "finish monday-report")
        try expectEqual(parse("email boss !!").priority, .high)
        try expectEqual(parse("tidy desk !low").priority, .low)
        try expectEqual(parse("Fix bug !HIGH tomorrow").title, "Fix bug")
        try expectEqual(parse("   ").title, "")
        try expectEqual(parse("may the fourth").title, "may the fourth", "'may' alone is not a date")
    }

    // MARK: Recurrence

    runner.run("Recurrence.nextOccurrences") {
        try expectEqual(RecurrenceRule.daily.next(after: at(2026, 3, 4, 9), calendar: cal), at(2026, 3, 5, 9))
        try expectEqual(RecurrenceRule.weekly.next(after: at(2026, 3, 4, 9), calendar: cal), at(2026, 3, 11, 9))
        try expectEqual(RecurrenceRule.monthly.next(after: at(2026, 1, 31, 9), calendar: cal), at(2026, 2, 28, 9))
        try expectEqual(RecurrenceRule.weekdays.next(after: at(2026, 3, 6, 9), calendar: cal), at(2026, 3, 9, 9), "Friday -> Monday")
        try expectEqual(RecurrenceRule.weekdays.next(after: at(2026, 3, 4, 9), calendar: cal), at(2026, 3, 5, 9))
        try expectTrue(RecurrenceRule.none.next(after: now, calendar: cal) == nil)
    }

    runner.run("Recurrence.completingARecurringTaskCreatesTheNextOne") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("prod-\(UUID().uuidString).sqlite")
        let store = try TaskStore(fileURL: dir)
        let t = TaskItem(title: "standup", dueDate: at(2026, 3, 6, 9), recurrence: .weekdays, hasDueTime: true)
        try store.add(t)
        let next = try store.spawnNextOccurrenceIfRecurring(after: t, calendar: cal)
        try expectEqual(next?.dueDate, at(2026, 3, 9, 9))
        try expectEqual(next?.recurrence, .weekdays)
        try expectEqual(next?.hasDueTime, true)
    }

    // MARK: Pomodoro

    runner.run("Pomodoro.longBreakAfterEveryFourthSession") {
        let p = PomodoroPlan.classic
        for n in 1...8 {
            let long = n % 4 == 0
            try expectEqual(p.isLongBreak(afterCompleted: n), long, "session \(n)")
            try expectEqual(p.breakMinutes(afterCompleted: n), long ? 15 : 5)
        }
        try expectEqual(p.isLongBreak(afterCompleted: 0), false)
    }

    runner.run("Pomodoro.dotsShowProgressThroughTheCycle") {
        let p = PomodoroPlan.classic
        try expectEqual(p.cycleDots(completed: 0), "⚪⚪⚪⚪")
        try expectEqual(p.cycleDots(completed: 2), "🍅🍅⚪⚪")
        try expectEqual(p.cycleDots(completed: 4), "🍅🍅🍅🍅")
        try expectEqual(p.cycleDots(completed: 5), "🍅⚪⚪⚪")
    }

    runner.run("Pomodoro.planClampsNonsense") {
        let p = PomodoroPlan(workMinutes: -5, shortBreakMinutes: 999, longBreakMinutes: 0, sessionsBeforeLongBreak: 99)
        try expectTrue(p.workMinutes >= 1 && p.shortBreakMinutes <= 60 && p.longBreakMinutes >= 1 && p.sessionsBeforeLongBreak <= 10)
        try expectEqual(PomodoroPlan.deepWork.workMinutes, 50)
    }

    runner.run("Pomodoro.settingsRoundTripAndDefaults") {
        let suite = "prod-settings-\(UUID().uuidString)"
        let s = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        try expectEqual(s.pomodoroPlan, .classic)
        try expectEqual(s.waterGoal, 8)
        try expectTrue(s.waterReminders && s.morningBrief && s.dailyRecap)
        try expectFalse(s.systemNotifications, "notifications are opt-in")
        try expectFalse(s.eyeBreaks)
        s.pomodoroPlan = PomodoroPlan(workMinutes: 40, shortBreakMinutes: 8, longBreakMinutes: 20, sessionsBeforeLongBreak: 3, autoStartNext: true)
        let again = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        try expectEqual(again.pomodoroPlan.workMinutes, 40)
        try expectEqual(again.pomodoroPlan.sessionsBeforeLongBreak, 3)
        try expectTrue(again.pomodoroPlan.autoStartNext)
        again.waterGoal = 9999
        try expectEqual(again.waterGoal, 30, "out-of-range values are clamped on read")
    }

    // MARK: Streaks

    runner.run("Streak.countsConsecutiveDays_andSurvivesUntilTodayEnds") {
        let days = [at(2026, 3, 4, 8), at(2026, 3, 3, 22), at(2026, 3, 2, 12), at(2026, 2, 28, 12)]
        try expectEqual(StreakCalculator.streak(activeDays: days, today: now, calendar: cal), 3)
        // Nothing yet today: yesterday's streak is still alive.
        try expectEqual(StreakCalculator.streak(activeDays: Array(days.dropFirst()), today: now, calendar: cal), 2)
        // A gap of two days breaks it.
        try expectEqual(StreakCalculator.streak(activeDays: [at(2026, 3, 1)], today: now, calendar: cal), 0)
        try expectEqual(StreakCalculator.streak(activeDays: [], today: now, calendar: cal), 0)
    }

    // MARK: Reminders and nudges

    runner.run("ReminderKinds.bedtimeBreaksQuietHours_butWaterDoesNot") {
        var c = ReminderQueue.Conditions()
        c.quietHours = true
        c.allowUrgentInQuietHours = false
        let bed = DueReminder(id: "b", kind: .bedtime, dueAt: now, title: "Bedtime", breaksQuietHours: true)
        let water = DueReminder(id: "w", kind: .water, dueAt: now, title: "Water")
        try expectTrue(ReminderQueue.allowed(bed, c))
        try expectFalse(ReminderQueue.allowed(water, c))
        c.quietHours = false
        c.focusActive = true
        try expectFalse(ReminderQueue.allowed(DueReminder(id: "e", kind: .eyeBreak, dueAt: now, title: "Eyes"), c), "no eye breaks during focus")
    }

    runner.run("TaskReminders.snoozedAndHandledStagesDoNotRefire") {
        var t = TaskItem(title: "x", dueDate: at(2026, 3, 4, 12), hasDueTime: true, remindBeforeMinutes: 30)
        let first = TaskReminderPlanner.next(for: t, now: now, calendar: cal)
        try expectEqual(first?.dueAt, at(2026, 3, 4, 11, 30))
        t.reminderHandledAt = at(2026, 3, 4, 11, 31)
        let second = TaskReminderPlanner.next(for: t, now: now, calendar: cal)
        try expectEqual(second?.urgency, .important, "after the early stage is handled the deadline itself is next")
        t.isCompleted = true
        try expectTrue(TaskReminderPlanner.next(for: t, now: now, calendar: cal) == nil)
    }

    // MARK: Focus history and export

    runner.run("FocusHistory.stoppedEarlySessionsCountByTimeSpent") {
        let store = try FocusHistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("fh-\(UUID().uuidString).sqlite"))
        try store.add(FocusSessionRecord(startedAt: now, endedAt: now.addingTimeInterval(1500), plannedFocusMinutes: 25, completedFully: true))
        try store.add(FocusSessionRecord(startedAt: now.addingTimeInterval(3600), endedAt: now.addingTimeInterval(4500), plannedFocusMinutes: 15, completedFully: false))
        try expectEqual(try store.focusMinutes(on: now, calendar: cal), 40)
        try expectEqual(try store.todayCompletedSessionCount(referenceDate: now, calendar: cal), 1)
    }

    runner.run("DataPortability.productivitySettingsRoundTrip_andOldExportsStillImport") {
        let src = AppSettings(defaults: UserDefaults(suiteName: "dp-src-\(UUID().uuidString)")!)
        src.waterGoal = 10
        src.eyeBreaks = true
        src.bedtimeHour = 22
        src.pomodoroPlan = PomodoroPlan(workMinutes: 30, shortBreakMinutes: 6, longBreakMinutes: 18, sessionsBeforeLongBreak: 3)
        let prog = ProgressionStore(defaults: UserDefaults(suiteName: "dp-p-\(UUID().uuidString)")!)
        prog.recordTaskCompleted()
        let data = try DataPortability.exportJSON(settings: src, progression: prog)
        let dst = AppSettings(defaults: UserDefaults(suiteName: "dp-dst-\(UUID().uuidString)")!)
        let dstProg = ProgressionStore(defaults: UserDefaults(suiteName: "dp-dp-\(UUID().uuidString)")!)
        try expectEqual(DataPortability.importJSON(data, into: dst, progression: dstProg), .success)
        try expectEqual(dst.waterGoal, 10)
        try expectTrue(dst.eyeBreaks)
        try expectEqual(dst.bedtimeHour, 22)
        try expectEqual(dst.pomodoroPlan.workMinutes, 30)
        try expectEqual(dstProg.tasksCompleted, 1)
        // An export from before productivity existed (no such keys) is still valid.
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "productivity")
        var progression = json["progression"] as! [String: Any]
        progression.removeValue(forKey: "tasksCompleted")
        progression.removeValue(forKey: "focusSessionsCompleted")
        json["progression"] = progression
        let old = try JSONSerialization.data(withJSONObject: json)
        let fresh = AppSettings(defaults: UserDefaults(suiteName: "dp-old-\(UUID().uuidString)")!)
        try expectEqual(DataPortability.importJSON(old, into: fresh, progression: ProgressionStore(defaults: UserDefaults(suiteName: "dp-oldp-\(UUID().uuidString)")!)), .success)
        try expectEqual(fresh.waterGoal, 8, "missing productivity keeps defaults")
    }

    runner.run("DataPortability.outOfRangeProductivityValuesAreRejected") {
        let src = AppSettings(defaults: UserDefaults(suiteName: "dp-bad-\(UUID().uuidString)")!)
        let prog = ProgressionStore(defaults: UserDefaults(suiteName: "dp-badp-\(UUID().uuidString)")!)
        var env = DataPortability.export(settings: src, progression: prog)
        env.productivity?.waterGoal = 500
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(env)
        switch DataPortability.decodeAndValidate(data) {
        case .failure(.outOfRange("productivity.waterGoal")): break
        default: try fail("expected outOfRange(productivity.waterGoal)")
        }
    }
}

func runAppAwarenessTests(_ runner: TestRunner) {
    runner.run("AppAwareness.categorisesCommonAppsByBundleID") {
        try expectEqual(AppCategory.category(forBundleID: "com.apple.dt.Xcode"), .coding)
        try expectEqual(AppCategory.category(forBundleID: "com.microsoft.VSCode"), .coding)
        try expectEqual(AppCategory.category(forBundleID: "us.zoom.xos"), .meeting)
        try expectEqual(AppCategory.category(forBundleID: "com.tinyspeck.slackmacgap"), .chatting)
        try expectEqual(AppCategory.category(forBundleID: "com.apple.mail"), .email)
        try expectEqual(AppCategory.category(forBundleID: "com.spotify.client"), .music)
        try expectEqual(AppCategory.category(forBundleID: "com.figma.Desktop"), .design)
        try expectEqual(AppCategory.category(forBundleID: "com.apple.Safari"), .browsing)
        try expectEqual(AppCategory.category(forBundleID: "com.google.Chrome"), .browsing)
        try expectEqual(AppCategory.category(forBundleID: "com.apple.finder"), nil)
        try expectEqual(AppCategory.category(forBundleID: ""), nil)
    }

    runner.run("AppAwareness.everyCategoryHasItsOwnMessages_andTheSettingIsOffByDefault") {
        for c in AppCategory.allCases {
            try expectTrue(PetMessageBook.lines(c.messageCategory, name: "x").count >= 4, "\(c)")
        }
        try expectFalse(AppSettings(defaults: UserDefaults(suiteName: "aa-\(UUID().uuidString)")!).appAwareChatter)
    }
}
