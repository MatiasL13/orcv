import CoreGraphics
import Foundation

func assertEqual(_ lhs: String?, _ rhs: String?, _ message: String) {
    if lhs != rhs {
        fputs("FAIL: \(message) (\(lhs ?? "nil") vs \(rhs ?? "nil"))\n", stderr)
        exit(1)
    }
}

func window(
    owner: String,
    rect: CGRect,
    layer: Int = 0,
    alpha: Double = 1.0,
    pid: pid_t = 1
) -> [String: Any] {
    [
        kCGWindowOwnerName as String: owner,
        kCGWindowLayer as String: layer,
        kCGWindowAlpha as String: alpha,
        kCGWindowOwnerPID as String: pid,
        kCGWindowBounds as String: rect.dictionaryRepresentation as! [String: Any],
    ]
}

let display = CGRect(x: 240, y: -1449, width: 1600, height: 1200)
let full = CGRect(x: 240, y: -1449, width: 1600, height: 1200)

func testFrontmostWins() {
    let windows = [
        window(owner: "Comet", rect: full),
        window(owner: "Slack", rect: full),
    ]
    assertEqual(FrontmostAppProbe.ownerName(in: display, windows: windows), "Comet", "front to back order")
}

func testTitleBarSliverIsSkipped() {
    // Real case: apps publish a 43pt title bar ahead of the real window.
    let windows = [
        window(owner: "Chrome", rect: CGRect(x: 240, y: -1366, width: 1600, height: 43)),
        window(owner: "Comet", rect: full),
    ]
    assertEqual(FrontmostAppProbe.ownerName(in: display, windows: windows), "Comet", "sliver skipped")
}

func testOtherLayersAndDisplaysIgnored() {
    let windows = [
        window(owner: "Menu Bar", rect: full, layer: 25),
        window(owner: "Elsewhere", rect: CGRect(x: -1360, y: -1200, width: 1600, height: 1200)),
        window(owner: "Comet", rect: full),
    ]
    assertEqual(FrontmostAppProbe.ownerName(in: display, windows: windows), "Comet", "layer and display filters")
}

func testStraddlingWindowMatchesByCenter() {
    // Half on this display, center on the neighbour: not ours.
    let straddling = CGRect(x: 1040, y: -1449, width: 1600, height: 1200)
    assertEqual(
        FrontmostAppProbe.ownerName(in: display, windows: [window(owner: "Split", rect: straddling)]),
        nil,
        "center outside display"
    )
}

func testOwnPIDAndInvisibleSkipped() {
    let windows = [
        window(owner: "orcv", rect: full, pid: 99),
        window(owner: "Ghost", rect: full, alpha: 0.0),
        window(owner: "Comet", rect: full),
    ]
    assertEqual(
        FrontmostAppProbe.ownerName(in: display, windows: windows, excludingPID: 99),
        "Comet",
        "self and invisible windows skipped"
    )
}

func testEmptyDesktop() {
    assertEqual(FrontmostAppProbe.ownerName(in: display, windows: []), nil, "no windows")
}

func runAllTests() {
    testFrontmostWins()
    testTitleBarSliverIsSkipped()
    testOtherLayersAndDisplaysIgnored()
    testStraddlingWindowMatchesByCenter()
    testOwnPIDAndInvisibleSkipped()
    testEmptyDesktop()
    print("FrontmostAppProbe tests passed")
}

@main
struct FrontmostAppProbeTestRunner {
    static func main() {
        runAllTests()
    }
}
