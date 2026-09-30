import Foundation

/// Short, plain observations about the last seven days -- only ones that are true and worth saying.
/// No scores, no rankings against other people.
public enum WeekInsights {
    public static func lines(labels: [String], focusMinutes: [Int], tasks: [Int], goalMinutes: Int) -> [String] {
        guard labels.count == focusMinutes.count, labels.count == tasks.count else { return [] }
        var out: [String] = []
        if let best = focusMinutes.enumerated().max(by: { $0.element < $1.element }), best.element > 0 {
            out.append("Best focus day: \(labels[best.offset]) (\(best.element) min)")
        }
        if goalMinutes > 0 {
            let hit = focusMinutes.filter { $0 >= goalMinutes }.count
            if hit > 0 { out.append("Focus goal reached \(hit) of \(labels.count) days") }
        }
        let activeDays = focusMinutes.filter { $0 > 0 }.count
        if activeDays >= 2 {
            out.append("About \(focusMinutes.reduce(0, +) / activeDays) min of focus on the days you focused")
        }
        if let busiest = tasks.enumerated().max(by: { $0.element < $1.element }), busiest.element >= 2 {
            out.append("Most tasks done: \(labels[busiest.offset]) (\(busiest.element))")
        }
        return out
    }
}
