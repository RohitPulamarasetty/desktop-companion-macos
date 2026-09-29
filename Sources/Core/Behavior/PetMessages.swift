import Foundation

/// What the pet says, and when it's allowed to say it. Deterministic (a
/// seeded random source picks among lines), local, no AI. Every category
/// has a cooldown and the same line is never used twice in a row, so the
/// pet never spams or repeats itself.
public enum MessageCategory: String, CaseIterable {
    case welcome, sleep, wake, idle, goodbye, returned, click, bored, play, lateNight, checkIn
    case annoyed, follow, comeHere, hide, found, explore, stay, stop
    case pet, grabbed, landed, notice, trick
    case moodHappy, moodCalm, moodCurious, moodSleepy, moodPlayful, moodExcited
    case morning, afternoon, evening
    case water, waterThanks, waterSkipped, waterGoal, breakAsk, breakThanks, breakSkipped, eyeBreak, stretch
    case focusStart, focusDone, focusHalf, focusLongBreak, focusStopped, task, allTasks, taskAdded
    case appCoding, appBrowsing, appEmail, appChatting, appMeeting, appMusic, appDesign, appWriting, appVideo
    case reminder, taskSoon, taskNow, taskTomorrow, overdue, snoozed, streak, bedtime, recap
}

public final class PetMessageBook {
    private let rng: RandomSource
    private var lastLine: [MessageCategory: String] = [:]
    private var lastSaid: [MessageCategory: Date] = [:]
    public var chattiness: Double = 1

    public init(rng: RandomSource) { self.rng = rng }

    /// Minimum time between two lines of the same category.
    public func cooldown(_ c: MessageCategory) -> TimeInterval {
        let chatty = max(chattiness, 0.5)
        switch c {
        case .idle, .bored, .play: return 4 * 60 / chatty
        case .moodHappy, .moodCalm, .moodCurious, .moodSleepy, .moodPlayful, .moodExcited: return 6 * 60 / chatty
        case .checkIn: return 30 * 60
        case .lateNight: return 3600
        case .morning, .afternoon, .evening: return 3 * 3600
        case .sleep: return 5 * 60
        case .task: return 10
        case .streak: return 1800
        case .bedtime: return 3600
        case .wake: return 30
        case .click: return 4
        case .pet: return 5
        case .grabbed, .landed: return 20
        case .notice: return 90
        case .appCoding, .appBrowsing, .appEmail, .appChatting, .appMeeting, .appMusic, .appDesign, .appWriting, .appVideo: return 25 * 60
        case .returned: return 10 * 60
        case .annoyed: return 20
        default: return 0
        }
    }

    public static func lines(_ c: MessageCategory, name: String) -> [String] {
        switch c {
        case .welcome: return ["Hi! I'm here. 👋", "Hello again! 🐾", "Ready when you are.", "Good to see you!", "heyyy 👀", "Oh good, you're here.", "I'm all yours today. 🐾", "Reporting for duty!", "Miss me?", "Let's have a good one."]
        case .sleep: return ["Zzz… nap time.", "Just resting my eyes…", "shhh... I'm sleepy 💤", "Five minutes…", "Wake me if anything fun happens.", "Nighty night… (it's daytime)", "*curls up*", "Recharging… 🔋"]
        case .wake: return ["*yawn* Oh, hi!", "Hm? I'm awake!", "*stretch* Hello!", "Was I snoring?", "Ooh, is it playtime?", "I had the best dream. 🌙", "Okay okay, I'm up!", "Back to the world we go."]
        case .idle: return ["Just enjoying the quiet.", "Hm, what's over there?", "I like it here.", "*looks around*", "Nice desktop you've got.", "Somebody's busy today.", "I could watch this cursor all day.", "Do windows ever get tired?", "I wonder what's in the Dock…", "This spot is perfect.", "Tiny break for me. 🐾", "Still here! Just checking.", "Working hard or hardly working? 😄", "*happy tail thoughts*", "So many pixels, so little time."]
        case .goodbye: return ["See you soon! 👋", "Bye for now!", "I'll keep the desktop warm.", "Come back soon!"]
        case .returned: return ["Oh, you're back!", "Welcome back! 🐾", "finally!! you're back 😭", "I missed you! …a little.", "You were gone forever! (it was a few minutes)", "Yay, human returned!"]
        case .click: return ["Hi! 👋", "Hehe!", "Yes? 😊", "Hello!", "heyyy 👀", "Boop!", "That tickles!", "You called?", "Present!", "What's up?", "Oh! Hi hi hi!", "You rang?", "Psst, I'm listening.", "Hey, that's my spot!", "Ready for anything."]
        case .pet: return ["Ooh, right there! ❤️", "That's the spot!", "Best human. 🥰", "More, please!", "I could get used to this.", "Aww. ❤️", "Purr… wait, wrong pet.", "You're my favorite.", "Mmm, yes. Perfect."]
        case .bored: return ["Hmm… what to do…", "*looks around*", "Is anything happening?", "Bored bored bored.", "Entertain me? 🥺", "I've counted every pixel.", "Want to play a game?", "Anything? Anyone?", "I could go for a chase."]
        case .play: return ["Wanna play? 🎾", "Hehe, catch me!", "Chase me! I dare you.", "Playtime? Playtime!", "Let's goooo! 🐾", "Race you to the cursor!", "I'm feeling zoomy."]
        case .lateNight: return ["It's getting late… 🌙", "Maybe time to wind down? 🌙", "The night shift, huh?", "Sleep is good, you know.", "Late night desktop vibes. ✨"]
        case .checkIn: return ["Hey… how's it going?", "Just checking in 🐾", "Doing okay?", "Need a friend? I'm right here.", "Long time no pat!", "You've been quiet. All good?"]
        case .annoyed: return ["Okay, okay, that's enough. 😒", "Hmph.", "Give me a minute…", "Too many clicks!", "I'm not a button. 😤", "Rude.", "Personal space, please."]
        case .follow: return ["Right behind you! 🐾", "Lead the way!", "Where to?", "I'm on your tail. Well, you're on mine.", "Following! 👀"]
        case .comeHere: return ["Coming!", "On my way!", "Zoom zoom!", "Right there!", "Did someone say come here?"]
        case .hide: return ["Ready or not… 🤫", "Come find me!", "You'll never find me!", "Shhh, hiding…", "*crouches quietly*"]
        case .found: return ["You found me! 🎉", "Ha! Found me!", "Okay, you're good.", "Again! Again!", "Best seeker ever!"]
        case .explore: return ["Let's see what's around…", "Ooh, exploring! 👀", "Adventure time!", "Secret spots, here I come.", "I smell something interesting."]
        case .stay: return ["Okay, staying put.", "I'll wait right here.", "Staying. Good dog.", "Not moving an inch."]
        case .stop: return ["Okay!", "Back to normal.", "Done! What now?", "All good."]
        case .grabbed: return ["Whoa!", "Hey! Put me down!", "Wheee!", "Where are we going?", "I'm flying! 🐾", "Careful, careful!"]
        case .landed: return ["Nice landing!", "Ah, solid ground.", "New spot, who dis?", "This view is fine too.", "Thanks for the ride!"]
        case .notice: return ["Oh hi!", "Is that a cursor I see?", "You're close! 👀", "I see you!", "Hey there!", "Hello, neighbor."]
        case .trick: return ["Ta-da!", "How was that?", "Treat? 👀", "Nailed it.", "Good dog, right?", "I've been practicing."]
        case .moodHappy: return ["Life is good. 😊", "Happy dog, happy day.", "I feel great!", "Everything's wonderful.", "Best day ever (so far)."]
        case .moodCalm: return ["Peaceful.", "Just vibing.", "Calm and cozy.", "Nothing to worry about.", "Slow and steady."]
        case .moodCurious: return ["What's that over there?", "I need to investigate. 🔍", "Curiouser and curiouser…", "Hmm, interesting…", "I wonder what happens if…"]
        case .moodSleepy: return ["*yawn* Sleepy…", "My eyes are heavy…", "Maybe a tiny nap?", "So. Sleepy.", "Nap o'clock soon."]
        case .moodPlayful: return ["I've got the zoomies!", "Wanna play? 🎾", "Feeling silly today!", "Catch me if you can!", "So much energy!"]
        case .moodExcited: return ["Yay yay yay! 🎉", "This is amazing!", "I can't stop wagging!", "Best. Moment. Ever.", "Woohoo! ✨"]
        case .water: return ["Water break? 💧", "Sip of water? 💧", "Hydration check! 💧", "Your water bottle misses you. 💧", "Glass of water, please? 🥤", "Stay hydrated, friend! 💧"]
        case .waterThanks: return ["Good job! 💧", "Refreshing! 💧", "Nice, that's the spirit 💧", "Hydration hero! 🏆", "Glug glug! 💦"]
        case .waterSkipped: return ["Okay, later then.", "No problem, I'll ask again soon.", "Your call! 💧", "No worries, water can wait a bit."]
        case .waterGoal: return ["Daily water goal reached! 🎉💧", "Fully hydrated — champion!", "That's the goal! Gold star ⭐", "Water goal smashed! Cheers! 🥂"]
        case .breakAsk: return ["You've been focused for a while. Take a short break?", "Time to stretch a little?", "Eyes and back could use a breather.", "Quick break? I'll keep your seat warm. 🐾"]
        case .breakThanks: return ["Enjoy your break! 🌿", "Stretch time! 🌿", "Go on, walk around a bit!", "Back in a few minutes, yes?"]
        case .breakSkipped: return ["Alright, carry on!", "Okay, I'll let you work.", "I'll check again later.", "Fine, but your eyes will remember."]
        case .eyeBreak: return ["20-20-20: look at something 20 feet away for 20 seconds. 👀", "Give your eyes a rest — look out the window! 👀", "Blink blink! Look far away for a moment. 👀", "Eye break! Focus on something distant."]
        case .stretch: return ["Roll your shoulders! 🧘", "Stand up and stretch for a minute.", "Posture check! Sit up tall. 🧘", "Wiggle your fingers and wrists. ✋"]
        case .focusStart: return ["Let's focus. 🎯", "Focus mode. I'll be quiet.", "You've got this. 🎯", "we've got this.", "Deep breath. Begin!", "I'll guard the desktop while you work."]
        case .focusDone: return ["Nice work! ✨", "Focus session done! ✨", "That was a good one. ✨", "HURRAY!! 🎉", "Pomodoro complete! 🍅", "You crushed it!"]
        case .focusHalf: return ["Halfway there! 🎯", "Half the session done — keep going!", "You're in the zone. ✨", "Halfway through. Keep it steady."]
        case .focusLongBreak: return ["Four in a row! Take a long break. 🌴", "Long break earned. You've done four sessions! 🏆", "You earned a proper rest. 🌴", "Big break time — stretch, snack, breathe."]
        case .focusStopped: return ["Session stopped. No worries.", "Okay, we'll go again later.", "Stopped early — that's fine. 🐾", "Every minute you focused still counts."]
        case .task: return ["Nice! One less thing. ✨", "Done and done!", "Ticked off! ✓", "you did it!! 🎉", "Another one bites the dust!", "Look at you go!", "Productive human alert! 🚨"]
        case .allTasks: return ["Everything's done for today! 🎉", "All clear! 🎉", "Task list: empty. Legend! 🏆", "Nothing left! Treat time? 🦴"]
        case .taskAdded: return ["Added! I'll keep an eye on it. 👀", "Got it, noted.", "On the list! ✍️", "Consider it remembered."]
        case .reminder: return ["Psst! A reminder for you.", "Don't forget this one!", "Heads up! 🔔", "Knock knock — reminder time."]
        case .taskSoon: return ["Hey! You have something coming up.", "Heads-up: this is coming up soon.", "Coming up shortly — ready?", "Just a heads-up, it's almost time."]
        case .taskNow: return ["This is due now!", "It's time for this one!", "Now's the moment! ⏰", "Time's up — this one's due!"]
        case .taskTomorrow: return ["Gentle heads-up for tomorrow.", "Just so you know, this is due tomorrow.", "Tomorrow's task, early warning. 📅", "Plan ahead: this is due tomorrow."]
        case .overdue: return ["This one is overdue — want to reschedule?", "Overdue! No judgment, let's fix it.", "That task slipped past. Snooze or finish it?", "Overdue, but never too late to start. 💪", "This one's been waiting. Shall we?"]
        case .snoozed: return ["Okay, I'll remind you later.", "Got it, later then.", "Snoozed. I'll be back! ⏰", "Later it is. Don't forget me! 🐾"]
        case .streak: return ["You're on a roll! 🔥", "Unstoppable today! 🔥", "Streak! Keep it going! 🔥", "Look at that momentum! 🔥", "Keep the streak alive! 🔥"]
        case .bedtime: return ["It's getting late — time to wrap up soon? 🌙", "Bedtime approaches. Save your work! 🌙", "Sleep is productive too. 😴", "Tomorrow is another day. Save and rest. 🌙", "Screens off soon? Your future self says thanks. 😴"]
        case .recap: return ["Good work today. 🌟", "Day wrapped up nicely.", "That's a wrap for today! 🎬", "Proud of you today. 🐾", "Not bad at all. Rest up!"]
        case .appCoding: return ["Ooh, code! Don't forget to commit. 💻", "Ship it! 🚀", "Bugs fear you.", "I believe in your semicolons.", "Tests first, right? 😉"]
        case .appBrowsing: return ["Surfing the web? 🌐", "So many tabs… I'm dizzy.", "Found anything interesting?", "Research or rabbit hole? 🐇", "Tab count: too many."]
        case .appEmail: return ["Inbox time. You've got this. ✉️", "Reply, archive, repeat.", "Inbox zero is a myth, but try!", "Emails, ugh. I'll wait here."]
        case .appChatting: return ["Chatty chatty! 💬", "Say hi from me!", "Somebody's popular today.", "Don't forget to look up sometimes. 👀", "Typing… typing… 💭"]
        case .appMeeting: return ["Good luck with the meeting! 🤞", "I'll be extra quiet. 🤫", "You're on mute, right?", "Smile, you're on camera! 😄"]
        case .appMusic: return ["Nice tunes! 🎵", "I'm bopping along. 🎶", "Turn it up!", "This one's a bop."]
        case .appDesign: return ["Pixel perfect! ✨", "Ooh, pretty colors. 🎨", "Art time!", "Make it pop!"]
        case .appWriting: return ["Words, words, words. ✍️", "I'll be quiet while you write.", "Blank page? Just start!", "Don't forget to save. 💾"]
        case .appVideo: return ["Movie time? 🍿", "Save me some popcorn!", "Shh, it's the good part.", "Enjoy the show! 🎬"]
        case .morning: return ["Good morning! ☀️", "Rise and shine!", "Morning! Ready for a great day?", "Fresh day, fresh pixels."]
        case .afternoon: return ["Good afternoon! 🌤️", "Halfway through the day!", "Afternoon slump? I'm here.", "Hope your day's going well."]
        case .evening: return ["Good evening! 🌆", "Winding down soon?", "The day's almost done.", "Evening, friend."]
        }
    }

    /// A few lines flavoured by temperament, mixed into idle/click chatter.
    public static func traitLines(_ c: MessageCategory, trait: String) -> [String] {
        switch (c, trait) {
        case (.idle, "curious"): return ["Ooh, what's that?", "I wonder what's up there…", "So many things to sniff out."]
        case (.idle, "calm"), (.idle, "gentle"), (.idle, "dreamy"): return ["Just enjoying the moment.", "Nice and cozy.", "Breathe in… breathe out…"]
        case (.idle, "playful"), (.idle, "energetic"): return ["Wanna play? 🎾", "So much to explore!", "I can't sit still!"]
        case (.idle, "mischievous"): return ["Heh. Nothing to see here.", "*plotting something*", "I didn't do it."]
        case (.idle, "loyal"): return ["Right here with you. 🐾", "Always by your side."]
        case (.idle, "friendly"): return ["Just hanging out. 😊", "Glad you're here."]
        case (.idle, "affectionate"): return ["Can I sit closer?", "I like being near you. ❤️"]
        case (.click, "playful"), (.click, "energetic"): return ["Boop! ✨", "Again! Again!", "Play with me!"]
        case (.click, "calm"), (.click, "gentle"), (.click, "dreamy"): return ["Mm, hello.", "Hi there.", "Oh, hello you."]
        case (.click, "curious"): return ["Ooh, hi!", "What's up? 👀", "Whatcha doing?"]
        case (.click, "mischievous"): return ["Heh, caught me.", "You found me! 😏", "What do you want, hm?"]
        case (.click, "loyal"): return ["Always here for you. 🐾"]
        case (.click, "friendly"): return ["Hey there! 😊"]
        case (.click, "affectionate"): return ["Hi hi hi! ❤️", "Come here, you!"]
        case (.pet, "affectionate"), (.pet, "loyal"): return ["I love you too. ❤️", "Never stop."]
        case (.pet, "mischievous"): return ["Okay, you can keep doing that.", "Bribery works."]
        case (.bored, "energetic"), (.bored, "playful"): return ["I NEED to run!", "Zoomies in 3… 2…"]
        default: return []
        }
    }

    /// A couple of lines that only enter the pool once the companion is
    /// genuinely familiar with the user -- recognition, not a
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
