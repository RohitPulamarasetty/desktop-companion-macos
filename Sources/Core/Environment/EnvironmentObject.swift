import Foundation

/// A placeable object in the pet's environment. Deliberately
/// small: no inventory, no ownership, no database -- an id, a kind, a
/// position, and whether it's currently usable. `PetContext` never holds
/// this type directly (mirroring how it never holds raw cursor state
/// beyond x/y) -- the app layer resolves the object the pet actually
/// cares about right now (see `EnvironmentObject.nearestAvailable`) and
/// feeds just that position into `PetContext`, the same pattern already
/// used for `cursorX`/`cursorY`.
public enum EnvironmentObjectKind: String, CaseIterable, Codable {
    /// The only object with real behavior today. Food, water and toys are
    /// not offered: no character has art for them, and a fake object with no
    /// behavior would be a dead feature.
    case bed
}

public struct EnvironmentObject: Equatable, Codable {
    public let id: String
    public let kind: EnvironmentObjectKind
    public var x: Double
    public var y: Double
    /// False while the object is mid-use, hidden, or otherwise not
    /// something the pet should path toward right now.
    public var isAvailable: Bool

    public init(id: String, kind: EnvironmentObjectKind, x: Double, y: Double, isAvailable: Bool = true) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.isAvailable = isAvailable
    }

    /// Discovery: the nearest available object of `kind` to `(petX, petY)`,
    /// or nil if none exists/qualifies. This is the one place "is an
    /// object usable" is decided -- callers never scatter their own
    /// coordinate/availability checks.
    public static func nearestAvailable(of kind: EnvironmentObjectKind, in objects: [EnvironmentObject], fromX petX: Double, fromY petY: Double) -> EnvironmentObject? {
        objects
            .filter { $0.kind == kind && $0.isAvailable }
            .min { a, b in
                let da = (a.x - petX) * (a.x - petX) + (a.y - petY) * (a.y - petY)
                let db = (b.x - petX) * (b.x - petX) + (b.y - petY) * (b.y - petY)
                return da < db
            }
    }
}
