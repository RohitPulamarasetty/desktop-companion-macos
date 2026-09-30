import Foundation

/// What a line like `call mom tomorrow 5pm !high every week remind 30m before` means.
public struct ParsedTask: Equatable {
    public var title: String
    public var dueDate: Date?
    public var hasDueTime = false
    public var priority: TaskPriority = .medium
    public var recurrence: RecurrenceRule = .none
    public var remindBeforeMinutes: Int?
    /// Things the user should know before saving: something typed was ignored or looks unintended.
    public var warnings: [String] = []
    public init(title: String) { self.title = title }
}

/// A small, deterministic natural-language parser for quick task capture.
/// It understands (case-insensitively, anywhere in the line):
///
/// - **dates**: `today`, `tonight`, `tomorrow`, `mon`…`sunday` / `next friday`, `in 3 days`, `in 2 weeks`,
///   `2026-10-05`, `oct 5`, `5 oct`
/// - **times**: `5pm`, `at 5:30 pm`, `17:00`, `noon`, `midnight`, `morning`, `afternoon`, `evening`, `in 45 min`, `in 2 hours`
/// - **priority**: `!high`, `!!`, `!low`, `!med`
/// - **repeat**: `daily`, `every day`, `weekdays`, `every weekday`, `weekly`, `every week`, `monthly`, `every month`, `every monday`
/// - **reminder**: `remind 30m before`, `remind 1 hour before`, `remind 1 day before`
///
/// Whatever is left is the title. Nothing is guessed: if a date word isn't recognised it stays in the title.
public enum QuickAddParser {
    private static let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
                                   "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7]
    private static let months = ["jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4, "may": 5,
                                 "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
                                 "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12]

    public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedTask {
        var text = " " + input.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        var result = ParsedTask(title: "")
        var day: Date?
        var time: (hour: Int, minute: Int)?
        var relative: Date?

        // Removes the first match of `pattern` and returns its capture groups (lowercased).
        func take(_ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                if let r = Range(m.range(at: i), in: text) { groups.append(String(text[r]).lowercased()) } else { groups.append("") }
            }
            if let r = Range(m.range(at: 0), in: text) { text.replaceSubrange(r, with: " ") }
            return groups
        }
        let startOfToday = calendar.startOfDay(for: now)
        func add(_ component: Calendar.Component, _ n: Int, to d: Date) -> Date { calendar.date(byAdding: component, value: n, to: d) ?? d }

        // Priority
        if let g = take(#"(?<=\s)!(high|h|!|low|l|med|medium|normal)(?=\s)"#) {
            switch g[1] { case "high", "h", "!": result.priority = .high; case "low", "l": result.priority = .low; default: result.priority = .medium }
        }
        // Reminder before
        if let g = take(#"(?<=\s)remind(?:er)?(?: me)?\s+(\d+)\s*(m|min|mins|minutes?|h|hr|hrs|hours?|d|days?)\s+before(?=\s)"#) {
            let n = Int(g[1]) ?? 0
            let unit = g[2]
            result.remindBeforeMinutes = unit.hasPrefix("d") ? n * 1440 : (unit.hasPrefix("h") ? n * 60 : n)
        } else if let g = take(#"(?<=\s)remind(?:er)?(?: me)?\s+(\d+)(m|h|d)(?: before)?(?=\s)"#) {
            let n = Int(g[1]) ?? 0
            result.remindBeforeMinutes = g[2] == "d" ? n * 1440 : (g[2] == "h" ? n * 60 : n)
        }
        // Recurrence
        if take(#"(?<=\s)(?:every\s+weekdays?|weekdays)(?=\s)"#) != nil { result.recurrence = .weekdays }
        else if take(#"(?<=\s)(?:every\s+(?:day|morning|evening)|daily)(?=\s)"#) != nil { result.recurrence = .daily }
        else if take(#"(?<=\s)(?:every\s+month|monthly)(?=\s)"#) != nil { result.recurrence = .monthly }
        else if let g = take(#"(?<=\s)every\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday|sun|mon|tues?|wed|thurs?|fri|sat)(?=\s)"#) {
            result.recurrence = .weekly
            if let wd = weekdays[g[1]] { day = nextWeekday(wd, after: startOfToday, calendar: calendar, includeToday: true) }
        } else if take(#"(?<=\s)(?:every\s+week|weekly)(?=\s)"#) != nil { result.recurrence = .weekly }

        // Relative offsets: in 45 min / in 2 hours / in 3 days / in 2 weeks
        if let g = take(#"(?<=\s)in\s+(\d+)\s*(m|min|mins|minutes?|h|hr|hrs|hours?|d|days?|w|weeks?)(?=\s)"#) {
            let n = Int(g[1]) ?? 0
            let unit = g[2]
            if unit.hasPrefix("w") { day = add(.day, 7 * n, to: startOfToday) }
            else if unit.hasPrefix("d") { day = add(.day, n, to: startOfToday) }
            else if unit.hasPrefix("h") { relative = now.addingTimeInterval(Double(n) * 3600) }
            else { relative = now.addingTimeInterval(Double(n) * 60) }
        }
        // Explicit dates
        let beforeISO = text
        if let g = take(#"(?<=\s)(\d{4})-(\d{1,2})-(\d{1,2})(?=\s)"#), let y = Int(g[1]), let mo = Int(g[2]), let d = Int(g[3]) {
            if let valid = Self.validDate(y, mo, d, calendar: calendar) { day = valid }
            else { text = beforeISO } // not a real date (2026-13-45): leave it in the title rather than dropping it silently
        } else if let g = take(#"(?<=\s)(?:on\s+)?(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?(?=\s)"#),
                  let mo = months[g[1]], let d = Int(g[2]) {
            if let v = monthDay(mo, d, now: now, calendar: calendar) { day = v } else { text = beforeISO }
        } else if let g = take(#"(?<=\s)(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)(?=\s)"#),
                  let d = Int(g[1]), let mo = months[g[2]] {
            if let v = monthDay(mo, d, now: now, calendar: calendar) { day = v } else { text = beforeISO }
        }
        // Named days
        if day == nil, relative == nil {
            if take(#"(?<=\s)(?:the\s+)?day\s+after\s+tomorrow(?=\s)"#) != nil { day = add(.day, 2, to: startOfToday) }
            else if take(#"(?<=\s)tomorrow(?=\s)"#) != nil { day = add(.day, 1, to: startOfToday) }
            else if take(#"(?<=\s)tonight(?=\s)"#) != nil { day = startOfToday; time = (20, 0) }
            else if take(#"(?<=\s)today(?=\s)"#) != nil { day = startOfToday }
            else if let g = take(#"(?<=\s)(next\s+)?(?:on\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday|sun|mon|tues?|wed|thurs?|fri|sat)(?=\s)"#), let wd = weekdays[g[2]] {
                var d = nextWeekday(wd, after: startOfToday, calendar: calendar, includeToday: false)
                if !g[1].isEmpty { d = add(.day, 7, to: d) }
                day = d
            }
        }
        // Times
        if time == nil, relative == nil {
            if take(#"(?<=\s)noon(?=\s)"#) != nil { time = (12, 0) }
            else if take(#"(?<=\s)midnight(?=\s)"#) != nil { time = (0, 0) }
            else if let g = take(#"(?<=\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?=\s)"#), var h = Int(g[1]), h >= 1, h <= 12 {
                let pm = g[3].hasPrefix("p")
                if h == 12 { h = pm ? 12 : 0 } else if pm { h += 12 }
                time = (h, Int(g[2]) ?? 0)
            } else if let g = take(#"(?<=\s)(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s)"#), let h = Int(g[1]), let m = Int(g[2]) {
                time = (h, m)
            } else if let g = take(#"(?<=\s)at\s+([01]?\d|2[0-3])(?=\s)"#), let h = Int(g[1]) {
                // "at 5" is ambiguous: read 1-6 as afternoon/evening, 7-11 as morning, 12 as noon; 0 and 13-23 are literal.
                time = (h >= 1 && h <= 6 ? h + 12 : h, 0)
            } else if take(#"(?<=\s)(?:this\s+)?morning(?=\s)"#) != nil { time = (9, 0) }
            else if take(#"(?<=\s)(?:this\s+)?afternoon(?=\s)"#) != nil { time = (14, 0) }
            else if take(#"(?<=\s)(?:this\s+)?evening(?=\s)"#) != nil { time = (18, 0) }
        }

        if let relative {
            result.dueDate = relative
            result.hasDueTime = true
        } else if day != nil || time != nil {
            var base = day ?? startOfToday
            if let time {
                base = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base) ?? base
                // A bare time that already passed today means tomorrow.
                if day == nil, base <= now { base = add(.day, 1, to: base) }
                result.hasDueTime = true
            }
            result.dueDate = base
        }
        if result.remindBeforeMinutes != nil, result.dueDate == nil {
            result.remindBeforeMinutes = nil
            result.warnings.append("Reminder ignored: add a date or time")
        }
        if let due = result.dueDate, result.recurrence == .none {
            let passed = result.hasDueTime ? due < now : due < startOfToday
            if passed { result.warnings.append("That time has already passed") }
        }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        result.title = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;-–—"))
        return result
    }

    private static func nextWeekday(_ weekday: Int, after start: Date, calendar: Calendar, includeToday: Bool) -> Date {
        for offset in (includeToday ? 0 : 1)...7 {
            let d = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            if calendar.component(.weekday, from: d) == weekday { return d }
        }
        return start
    }

    /// A real calendar day, or nil. `Calendar.date(from:)` is lenient (Feb 30 rolls into March), so this checks the round trip.
    private static func validDate(_ y: Int, _ m: Int, _ d: Int, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == y && back.month == m && back.day == d ? date : nil
    }

    /// The next occurrence of month/day (this year, or next if it already passed); nil for impossible dates like Feb 30.
    private static func monthDay(_ month: Int, _ day: Int, now: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: now)
        let today = calendar.startOfDay(for: now)
        for y in [year, year + 1, year + 2, year + 3, year + 4] {
            if let d = validDate(y, month, day, calendar: calendar), d >= today { return d }
        }
        return nil
    }
}
