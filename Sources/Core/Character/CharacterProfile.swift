import Foundation

/// Plain-language description of a character, derived only from what the engine actually does with its
/// personality dials and from the art it actually has -- nothing is claimed that the behavior doesn't back.
public enum CharacterProfile {
    /// Up to three short lines about how the character behaves, strongest traits first. Empty for a neutral character.
    public static func temperament(_ p: Personality) -> [String] {
        // (deviation from neutral, line). Thresholds are deliberately wide so only real differences are described.
        var found: [(Double, String)] = []
        func add(_ v: Double, high: Double, low: Double, _ highLine: String, _ lowLine: String?) {
            if v >= high { found.append((v - 1, highLine)) }
            else if v <= low, let lowLine { found.append((1 - v, lowLine)) }
        }
        add(p.curiosity, high: 1.15, low: 0.85, "Curious: likes exploring and checking out your cursor.", "Settled: happy to stay put and watch.")
        add(p.affection, high: 1.25, low: 0.9, "Affectionate: warms up quickly and comes over to say hi.", "Independent: friendly, but keeps its distance.")
        add(p.roaming, high: 1.2, low: 0.8, "Energetic: moves around and plays more often.", "Relaxed: prefers a quiet corner to wandering.")
        add(p.restfulness, high: 1.25, low: 0.8, "Sleepy: naps and lingers in calm poses.", "Restless: rarely sits still for long.")
        add(p.playfulness, high: 1.15, low: 0.85, "Playful: zooms about and plays more.", "Sedate: plays less than most.")
        add(p.reactivity, high: 1.2, low: 0.85, "Expressive: reacts quickly when you click.", "Composed: takes things in stride.")
        add(p.chattiness, high: 1.2, low: 0.8, "Chatty: has plenty to say.", "Quiet: speaks up less often.")
        return found.sorted { $0.0 > $1.0 }.prefix(3).map(\.1)
    }

    /// What this character can actually do, from its available clips: activities first, then tricks.
    public static func abilities(clips: Set<String>) -> [String] {
        var config = PetBrain.Config(pointsPerPixel: 2, petWidth: 100, availableClips: clips)
        config.homeOnLeft = true
        let brain = PetBrain(config: config, x: 300, minX: 0, maxX: 1000, rng: SeededRandom(seed: 1))
        var ctx = PetContext()
        ctx.cursorX = 500
        ctx.cursorY = 100
        let activities = Activity.allCases.filter { brain.availability(of: $0, context: ctx) == .available }.map(\.displayName)
        return activities + brain.availableTricks.map(\.displayName)
    }
}
