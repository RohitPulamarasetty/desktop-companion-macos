import Foundation

/// Pure geometry for where the pet may be: no AppKit, unit tested.
public enum PetPlacement {
    public struct Display: Equatable {
        public let id: UInt32
        /// The usable area (menu bar and Dock excluded), bottom-left origin.
        public let visibleMinX: Double, visibleMinY: Double, visibleMaxX: Double, visibleMaxY: Double
        public init(id: UInt32, visibleMinX: Double, visibleMinY: Double, visibleMaxX: Double, visibleMaxY: Double) {
            self.id = id
            self.visibleMinX = visibleMinX
            self.visibleMinY = visibleMinY
            self.visibleMaxX = visibleMaxX
            self.visibleMaxY = visibleMaxY
        }
        public var width: Double { visibleMaxX - visibleMinX }
    }

    /// Range for the pet window's LEFT edge such that the whole frame stays
    /// inside the visible area. Never inverted: a pet wider than the screen
    /// pins to the left edge.
    public static func xRange(on d: Display, petWidth: Double, roamRange: RoamRange, homeOnLeft: Bool) -> (min: Double, max: Double) {
        var lo = d.visibleMinX
        var hi = max(d.visibleMinX, d.visibleMaxX - petWidth)
        if roamRange == .nearHome {
            let span = max(d.width / 3, petWidth * 4)
            if homeOnLeft { hi = min(hi, lo + span) } else { lo = max(lo, hi - span) }
        }
        return (lo, max(lo, hi))
    }

    public struct Area: Equatable {
        public let minX: Double, maxX: Double, minY: Double, maxY: Double
    }

    /// 2-D range for the pet's bottom-left corner so the WHOLE pet frame
    /// stays inside the visible area (below the menu bar, above/beside the
    /// Dock). Never inverted: a pet larger than the area pins to its corner.
    public static func area(on d: Display, petWidth: Double, petHeight: Double, roamRange: RoamRange, homeOnLeft: Bool) -> Area {
        let x = xRange(on: d, petWidth: petWidth, roamRange: roamRange, homeOnLeft: homeOnLeft)
        let minY = d.visibleMinY
        var maxY = max(minY, d.visibleMaxY - petHeight)
        if roamRange == .nearHome {
            maxY = min(maxY, minY + max((d.visibleMaxY - d.visibleMinY) / 3, petHeight * 2))
        }
        return Area(minX: x.min, maxX: x.max, minY: minY, maxY: max(minY, maxY))
    }

    /// The display the pet should live on. Keeps the assigned display while
    /// it exists; otherwise falls back to the primary (first) display. Nil
    /// only if there are no displays at all.
    public static func resolveDisplay(assigned: UInt32?, available: [Display]) -> Display? {
        if let assigned, let d = available.first(where: { $0.id == assigned }) { return d }
        return available.first
    }

    /// Where a drop lands: the display containing the pet's centre, or the
    /// nearest one if the centre is off every display.
    public static func displayForDrop(centerX: Double, centerY: Double, displays: [Display]) -> Display? {
        if let d = displays.first(where: { centerX >= $0.visibleMinX && centerX <= $0.visibleMaxX && centerY >= $0.visibleMinY - 200 && centerY <= $0.visibleMaxY + 200 }) {
            return d
        }
        return displays.min(by: { distance(centerX, centerY, $0) < distance(centerX, centerY, $1) })
    }

    private static func distance(_ x: Double, _ y: Double, _ d: Display) -> Double {
        let dx = max(d.visibleMinX - x, 0, x - d.visibleMaxX)
        let dy = max(d.visibleMinY - y, 0, y - d.visibleMaxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
