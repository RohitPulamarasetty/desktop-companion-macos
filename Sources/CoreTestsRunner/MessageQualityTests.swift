import Foundation
import Core

/// Reads the actual user-visible strings, not just their IDs.
func runMessageQualityTests(_ runner: TestRunner) {
    let traits = ["calm", "friendly", "dreamy", "loyal", "curious", "playful", "mischievous", "energetic", "gentle", "affectionate"]
    var everyLine: [(String, String)] = [] // (label, text)
    for c in MessageCategory.allCases {
        for l in PetMessageBook.lines(c, name: "Pet") { everyLine.append(("\(c)", l)) }
        for l in PetMessageBook.familiarLines(c) + PetMessageBook.recognitionLines(c) { everyLine.append(("\(c)/familiar", l)) }
        for t in traits { for l in PetMessageBook.traitLines(c, trait: t) { everyLine.append(("\(c)/\(t)", l)) } }
    }

    runner.run("MessageQuality.noSpeciesSpecificWords_thereAreDragonsCactiAndPlanets") {
        let banned = ["dog", "pup", "wag", "bark", "sniff", "purr", "meow", "fetch", "bone", "🦴", "good boy", "good girl", "treat time"]
        for (label, text) in everyLine {
            let lower = text.lowercased()
            for w in banned where lower.contains(w) && !(w == "pup" && lower.contains("puppet")) {
                // "Treat? 👀" (trick) is a generic ask; only whole species words are banned.
                try fail("\(label): \"\(text)\" contains \"\(w)\"")
            }
        }
    }

    runner.run("MessageQuality.noFalseTimeOrCountClaims") {
        let timeCategories: Set<String> = ["lateNight", "bedtime", "morning", "afternoon", "evening", "recap", "taskTomorrow", "goodbye"]
        for (label, text) in everyLine {
            let cat = String(label.split(separator: "/")[0])
            let lower = text.lowercased()
            if !timeCategories.contains(cat) {
                for w in ["daytime", "tonight", "this morning", "this evening", "nighty night", "good night"] {
                    try expectFalse(lower.contains(w), "\(label): \"\(text)\" claims a time of day")
                }
            }
            for w in ["four in a row", "three in a row", "you've done four", "a few minutes", "forever"] {
                try expectFalse(lower.contains(w), "\(label): \"\(text)\" makes a claim that may be false")
            }
        }
    }

    runner.run("MessageQuality.noDuplicateLinesAnywhere_norTwoCategoriesSharingAString") {
        var seen: [String: String] = [:]
        for (label, text) in everyLine {
            let key = text.lowercased()
            let cat = String(label.split(separator: "/")[0])
            // The same line may serve several trait groups of one category; two categories must not share a string.
            if let other = seen[key], other != cat { try fail("\"\(text)\" appears in both \(other) and \(cat)") }
            seen[key] = cat
        }
    }

    runner.run("MessageQuality.restrainedTone_noShoutingNoDoubleBangs_andBubbleSizedLength") {
        for (label, text) in everyLine {
            try expectFalse(text.contains("!!"), "\(label): \"\(text)\" is shouting")
            for word in text.split(whereSeparator: { !$0.isLetter }) where word.count >= 4 {
                try expectFalse(word == word.uppercased() && word.contains(where: \.isLetter), "\(label): \"\(text)\" has an ALL-CAPS word")
            }
            try expectTrue(text.count <= 100, "\(label): \"\(text)\" is \(text.count) characters")
        }
    }

    runner.run("MessageQuality.aBrandNewCompanion_neverPretendsToKnowYou") {
        for c in [MessageCategory.welcome, .returned] {
            let banned = Set(PetMessageBook.recognitionLines(c) + PetMessageBook.familiarLines(c))
            let book = PetMessageBook(rng: SeededRandom(seed: 4))
            var now = Date()
            for _ in 0..<300 {
                now.addTimeInterval(4 * 3600)
                if let l = book.line(c, name: "Pet", now: now, familiarity: 0.4) { try expectFalse(banned.contains(l), "new companion said \"\(l)\"") }
            }
        }
    }

    runner.run("MessageQuality.aFamiliarCompanion_canRecogniseYou") {
        let book = PetMessageBook(rng: SeededRandom(seed: 4))
        var now = Date()
        var sawRecognition = false
        let rec = Set(PetMessageBook.recognitionLines(.welcome))
        for _ in 0..<400 {
            now.addTimeInterval(4 * 3600)
            if let l = book.line(.welcome, name: "Pet", now: now, familiarity: 0.7), rec.contains(l) { sawRecognition = true }
        }
        try expectTrue(sawRecognition)
    }

    runner.run("Messages.ambientReactions_areRareAndNeverChainOntoOtherSpeech") {
        let book = PetMessageBook(rng: SeededRandom(seed: 1))
        try expectTrue(book.cooldown(.sleep) >= 15 * 60, "falling asleep is not worth a remark every few minutes")
        try expectTrue(book.cooldown(.notice) >= 4 * 60)
        try expectTrue(PetMessageBook.ambientCategories.isSuperset(of: [.notice, .sleep, .landed]))
        try expectTrue(PetMessageBook.ambientQuietGap >= 45)
    }

    runner.run("SpeechBudget.spontaneousTalkIsSpacedOut_longerAtNight_shorterForTheChatty") {
        let now = Date()
        try expectTrue(SpeechBudget.allows(now: now, lastSpontaneous: nil, chattiness: 1, hour: 14))
        try expectFalse(SpeechBudget.allows(now: now, lastSpontaneous: now.addingTimeInterval(-60), chattiness: 1, hour: 14), "a minute after the last remark is too soon")
        try expectTrue(SpeechBudget.allows(now: now, lastSpontaneous: now.addingTimeInterval(-8 * 60), chattiness: 1, hour: 14))
        try expectFalse(SpeechBudget.allows(now: now, lastSpontaneous: now.addingTimeInterval(-8 * 60), chattiness: 1, hour: 23), "quieter at night")
        try expectFalse(SpeechBudget.allows(now: now, lastSpontaneous: nil, lastSpoken: now.addingTimeInterval(-3), chattiness: 1, hour: 14), "no unprompted line right after a reaction")
        try expectTrue(SpeechBudget.allows(now: now, lastSpontaneous: nil, lastSpoken: now.addingTimeInterval(-180), chattiness: 1, hour: 14))
        try expectTrue(SpeechBudget.minimumGap(chattiness: 1.5, hour: 14) < SpeechBudget.minimumGap(chattiness: 1, hour: 14))
        try expectTrue(SpeechBudget.minimumGap(chattiness: 0.1, hour: 14) <= SpeechBudget.baseGap * 2, "even a silent character stays bounded")
    }
}
