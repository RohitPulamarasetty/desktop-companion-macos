import Foundation

/// What the pet says, and when it's allowed to say it. Deterministic (a
/// seeded random source picks among lines), local, no AI. Every category
/// has a cooldown and the same line is never used twice in a row, so the
/// pet never spams or repeats itself.
public enum MessageCategory: String, CaseIterable {
    case welcome, water, waterThanks, waterSkipped, breakAsk, breakThanks, breakSkipped
    case focusStart, focusDone, task, allTasks, sleep, wake, idle, celebration, goodbye, returned, click, reminder
    case bored, play, screenTime, lateNight, checkIn, streak, taskSoon, taskNow, taskTomorrow, snoozed
}

public final class PetMessageBook {
    private let rng: RandomSource
    private var lastLine: [MessageCategory: String] = [:]
    private var lastSaid: [MessageCategory: Date] = [:]
    public var chattiness: Double = 1

    public init(rng: RandomSource) { self.rng = rng }

    /// Minimum time between two lines of the same category.
    public func cooldown(_ c: MessageCategory) -> TimeInterval {
        switch c {
        case .idle, .bored, .play: return 25 * 60 / max(chattiness, 0.5)
        case .checkIn: return 2 * 3600
        case .lateNight: return 3600
        case .streak: return 1800
        case .sleep: return 10 * 60
        case .wake: return 45
        case .click: return 8
        case .task: return 15
        case .returned: return 10 * 60
        default: return 0
        }
    }

    public static func lines(_ c: MessageCategory, name: String) -> [String] {
        switch c {
        case .welcome: return ["Hi! I'm here. 👋", "Hello again! 🐾", "Ready when you are.", "Good to see you!", "heyyy 👀"]
        case .water: return ["Water break? 💧", "Sip of water? 💧", "Hydration check! 💧"]
        case .waterThanks: return ["Good job! 💧", "Refreshing! 💧", "Nice, that's the spirit 💧"]
        case .waterSkipped: return ["Okay, later then.", "No problem!"]
        case .breakAsk: return ["You've been focused for a while. Take a short break?", "Time to stretch a little?"]
        case .breakThanks: return ["Enjoy your break! 🌿", "Stretch time! 🌿"]
        case .breakSkipped: return ["Alright, carry on!", "Okay, I'll let you work."]
        case .focusStart: return ["Let's focus. 🎯", "Focus mode. I'll be quiet.", "You've got this. 🎯", "we've got this."]
        case .focusDone: return ["Nice work! ✨", "Focus session done! ✨", "That was a good one. ✨", "HURRAY!! 🎉"]
        case .task: return ["Nice! One less thing. ✨", "Done and done!", "Ticked off! ✓", "you did it!! 🎉"]
        case .allTasks: return ["Everything's done for today! 🎉", "All clear! 🎉"]
        case .sleep: return ["Zzz… nap time.", "Just resting my eyes…", "shhh... I'm sleepy 💤"]
        case .wake: return ["*yawn* Oh, hi!", "Hm? I'm awake!", "*stretch* Hello!"]
        case .idle: return ["Just enjoying the quiet.", "Hm, what's over there?", "I like it here.", "*looks around*", "what are we working on?"]
        case .celebration: return ["Yay! 🎉", "Woohoo! ✨", "you did it!! 🎉"]
        case .goodbye: return ["See you soon! 👋", "Bye for now!"]
        case .returned: return ["Oh, you're back!", "Welcome back! 🐾", "finally!! you're back 😭"]
        case .click: return ["Hi! 👋", "Hehe!", "Yes? 😊", "Hello!", "heyyy 👀"]
        case .reminder: return ["Psst! A reminder for you.", "Don't forget this one!"]
        case .bored: return ["Hmm… what to do…", "*looks around*", "Is anything happening?"]
        case .play: return ["Wanna play? 🎾", "Hehe, catch me!"]
        case .screenTime: return ["You've been staring at the screen for a while 👀", "Your eyes need a break 👀", "Time to look away for a minute? 👀"]
        case .lateNight: return ["It's getting late… 🌙", "Maybe time to wind down? 🌙"]
        case .checkIn: return ["Hey… how's it going?", "Just checking in 🐾", "Doing okay?", "you've been sitting there forever 😭"]
        case .streak: return ["You're on a roll! 🔥", "Unstoppable today! 🔥"]
        case .taskSoon: return ["Hey! You have something coming up.", "Heads-up: this is coming up soon."]
        case .taskNow: return ["This is due now!", "It's time for this one!"]
        case .taskTomorrow: return ["Gentle heads-up for tomorrow.", "Just so you know, this is due tomorrow."]
        case .snoozed: return ["Okay, I'll remind you later.", "Got it, later then."]
        }
    }

    /// A few lines flavoured by temperament, mixed into idle/click chatter.
    public static func traitLines(_ c: MessageCategory, trait: String) -> [String] {
        switch (c, trait) {
        case (.idle, "curious"): return ["Ooh, what's that?", "I wonder what's up there…"]
        case (.idle, "calm"), (.idle, "gentle"), (.idle, "dreamy"): return ["Just enjoying the moment.", "Nice and cozy."]
        case (.idle, "playful"), (.idle, "energetic"): return ["Wanna play? 🎾", "So much to explore!"]
        case (.idle, "mischievous"): return ["Heh. Nothing to see here.", "*plotting something*"]
        case (.idle, "loyal"): return ["Right here with you. 🐾"]
        case (.idle, "friendly"): return ["Just hanging out. 😊", "Glad you're here."]
        case (.click, "playful"), (.click, "energetic"): return ["Boop! ✨", "Again! Again!"]
        case (.click, "calm"), (.click, "gentle"), (.click, "dreamy"): return ["Mm, hello.", "Hi there."]
        case (.click, "curious"): return ["Ooh, hi!", "What's up? 👀"]
        case (.click, "mischievous"): return ["Heh, caught me.", "You found me! 😏"]
        case (.click, "loyal"): return ["Always here for you. 🐾"]
        case (.click, "friendly"): return ["Hey there! 😊"]
        default: return []
        }
    }

    /// A couple of lines that only enter the pool once the companion is
    /// genuinely familiar with the user (Stage 12) -- recognition, not a
    /// new emotional register. Kept to the two categories where "this
    /// character has known me a while" actually reads naturally; not
    /// spread across every category, per the brief's "small set" rule.
    public static func familiarLines(_ c: MessageCategory) -> [String] {
        switch c {
        case .returned: return ["Hey, there you are again. 🐾", "You're back — good."]
        case .click: return ["Heh, you again. 😊"]
        default: return []
        }
    }

    /// A line for the category, or nil if it's in cooldown. `force`
    /// ignores the cooldown (for direct answers to the user). `familiarity`
    /// (0...1, defaults to 1 for full backward compatibility with every
    /// existing caller) mixes in a couple of recognition lines once the
    /// companion is genuinely familiar -- see `familiarLines`.
    public func line(_ c: MessageCategory, name: String, trait: String = "friendly", now: Date, force: Bool = false, familiarity: Double = 1) -> String? {
        if !force, let last = lastSaid[c], now.timeIntervalSince(last) < cooldown(c) { return nil }
        var pool = Self.lines(c, name: name) + Self.traitLines(c, trait: trait)
        if familiarity >= 0.9 { pool += Self.familiarLines(c) }
        if pool.count > 1, let last = lastLine[c] { pool.removeAll { $0 == last } }
        guard !pool.isEmpty else { return nil }
        let pick = pool[min(pool.count - 1, Int(rng.nextUnit() * Double(pool.count)))]
        lastLine[c] = pick
        lastSaid[c] = now
        return pick
    }
}
