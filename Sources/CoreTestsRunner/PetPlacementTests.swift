import Foundation
import Core

func runPetPlacementTests(_ runner: TestRunner) {
    let main = PetPlacement.Display(id: 1, visibleMinX: 0, visibleMinY: 70, visibleMaxX: 1512, visibleMaxY: 950)
    let external = PetPlacement.Display(id: 2, visibleMinX: 1512, visibleMinY: 0, visibleMaxX: 1512 + 2560, visibleMaxY: 1415)

    runner.run("Placement.fullPetFrameStaysInsideVisibleArea") {
        let r = PetPlacement.xRange(on: main, petWidth: 93, roamRange: .wholeScreen, homeOnLeft: true)
        try expectEqual(r.min, 0)
        try expectEqual(r.max, 1512 - 93)
        let ext = PetPlacement.xRange(on: external, petWidth: 160, roamRange: .wholeScreen, homeOnLeft: true)
        try expectEqual(ext.min, 1512)
        try expectEqual(ext.max, 1512 + 2560 - 160)
    }

    runner.run("Placement.petWiderThanScreenNeverInvertsRange") {
        let tiny = PetPlacement.Display(id: 9, visibleMinX: 100, visibleMinY: 0, visibleMaxX: 150, visibleMaxY: 100)
        let r = PetPlacement.xRange(on: tiny, petWidth: 93, roamRange: .wholeScreen, homeOnLeft: true)
        try expectEqual(r.min, 100)
        try expectEqual(r.max, 100)
    }

    runner.run("Placement.nearHomeLimitsRangeToTheHomeCorner") {
        let left = PetPlacement.xRange(on: main, petWidth: 93, roamRange: .nearHome, homeOnLeft: true)
        try expectEqual(left.min, 0)
        try expectEqual(left.max, 504)
        let right = PetPlacement.xRange(on: main, petWidth: 93, roamRange: .nearHome, homeOnLeft: false)
        try expectEqual(right.max, 1512 - 93)
        try expectEqual(right.min, 1512 - 93 - 504)
    }

    runner.run("Placement.disconnectedDisplayFallsBackToPrimary") {
        try expectEqual(PetPlacement.resolveDisplay(assigned: 2, available: [main, external])?.id, 2)
        try expectEqual(PetPlacement.resolveDisplay(assigned: 2, available: [main])?.id, 1)
        try expectEqual(PetPlacement.resolveDisplay(assigned: nil, available: [main, external])?.id, 1)
        try expectTrue(PetPlacement.resolveDisplay(assigned: 1, available: []) == nil)
    }

    runner.run("Placement.dropChoosesDisplayUnderPetOrNearest") {
        try expectEqual(PetPlacement.displayForDrop(centerX: 2000, centerY: 500, displays: [main, external])?.id, 2)
        try expectEqual(PetPlacement.displayForDrop(centerX: 700, centerY: 400, displays: [main, external])?.id, 1)
        try expectEqual(PetPlacement.displayForDrop(centerX: -500, centerY: 400, displays: [main, external])?.id, 1)
    }

    runner.run("Placement.area_coversTheWholeUsableDesktopIncludingTheTop") {
        let a = PetPlacement.area(on: main, petWidth: 93, petHeight: 101, roamRange: .wholeScreen, homeOnLeft: true)
        try expectEqual(a.minX, 0)
        try expectEqual(a.maxX, 1512 - 93)
        try expectEqual(a.minY, 70)             // above the Dock
        try expectEqual(a.maxY, 950 - 101)      // whole pet stays below the menu bar
        let ext = PetPlacement.area(on: external, petWidth: 93, petHeight: 101, roamRange: .wholeScreen, homeOnLeft: true)
        try expectEqual(ext.maxY, 1415 - 101)
        let tiny = PetPlacement.Display(id: 5, visibleMinX: 0, visibleMinY: 0, visibleMaxX: 50, visibleMaxY: 50)
        let t = PetPlacement.area(on: tiny, petWidth: 93, petHeight: 101, roamRange: .wholeScreen, homeOnLeft: true)
        try expectEqual(t.maxY, t.minY)
        try expectEqual(t.maxX, t.minX)
    }
}
