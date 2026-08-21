import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

let mainRect = CGRect(x: 0, y: 0, width: 3440, height: 1440)
let size = CGSize(width: 1600, height: 1200)

func testOverlappingBlockIsPushedAboveMainDisplay() {
    // A virtual display sitting at the origin is exactly the Dock-stealing case.
    let origins: [CGDirectDisplayID: CGPoint] = [
        58: CGPoint(x: 0, y: 0),
        59: CGPoint(x: 1600, y: 0),
    ]
    let sizes: [CGDirectDisplayID: CGSize] = [58: size, 59: size]
    let result = DisplayArrangement.shiftClearingMainDisplay(
        origins: origins, sizes: sizes, mainDisplayRect: mainRect
    )
    for (id, origin) in result {
        let rect = CGRect(origin: origin, size: size)
        if rect.intersects(mainRect) { fail("display \(id) still overlaps the main display: \(rect)") }
    }
    // Relative layout must survive: both were on the same row, 1600pt apart.
    guard let a = result[58], let b = result[59] else { fail("lost a display") }
    if abs(a.y - b.y) > 0.001 { fail("row alignment lost: \(a) \(b)") }
    if abs((b.x - a.x) - 1600) > 0.001 { fail("horizontal spacing changed: \(a) \(b)") }
    if abs(a.y - (-1200)) > 0.001 { fail("expected the block parked just above the main display, got \(a)") }
}

func testNonOverlappingBlockIsLeftAlone() {
    let origins: [CGDirectDisplayID: CGPoint] = [58: CGPoint(x: -70, y: -1200)]
    let result = DisplayArrangement.shiftClearingMainDisplay(
        origins: origins, sizes: [58: size], mainDisplayRect: mainRect
    )
    if result[58] != CGPoint(x: -70, y: -1200) { fail("moved a block that was already clear: \(result)") }
}

func testPartialOverlapShiftsEveryDisplay() {
    // Only one of the two overlaps, but the block must move as a unit.
    let origins: [CGDirectDisplayID: CGPoint] = [
        58: CGPoint(x: 100, y: -600),
        59: CGPoint(x: 100, y: -1800),
    ]
    let sizes: [CGDirectDisplayID: CGSize] = [58: size, 59: size]
    let result = DisplayArrangement.shiftClearingMainDisplay(
        origins: origins, sizes: sizes, mainDisplayRect: mainRect
    )
    for (id, origin) in result {
        if CGRect(origin: origin, size: size).intersects(mainRect) { fail("\(id) overlaps: \(origin)") }
    }
    guard let a = result[58], let b = result[59] else { fail("lost a display") }
    if abs((a.y - b.y) - 1200) > 0.001 { fail("vertical spacing changed: \(a) \(b)") }
}

func testDegenerateInputs() {
    if !DisplayArrangement.shiftClearingMainDisplay(origins: [:], sizes: [:], mainDisplayRect: mainRect).isEmpty {
        fail("empty input should stay empty")
    }
    let origins: [CGDirectDisplayID: CGPoint] = [58: .zero]
    let unknownSize = DisplayArrangement.shiftClearingMainDisplay(
        origins: origins, sizes: [:], mainDisplayRect: mainRect
    )
    if unknownSize[58] != .zero { fail("without a size we cannot judge overlap; must not move") }
    let noMain = DisplayArrangement.shiftClearingMainDisplay(
        origins: origins, sizes: [58: size], mainDisplayRect: .zero
    )
    if noMain[58] != .zero { fail("no main rect means no shift") }
}

func runAllTests() {
    testOverlappingBlockIsPushedAboveMainDisplay()
    testNonOverlappingBlockIsLeftAlone()
    testPartialOverlapShiftsEveryDisplay()
    testDegenerateInputs()
    print("DisplayArrangement tests passed")
}

@main
struct DisplayArrangementTestRunner {
    static func main() {
        runAllTests()
    }
}
