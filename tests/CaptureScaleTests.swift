import CoreGraphics
import Foundation

func assertSize(_ lhs: CGSize, _ rhs: CGSize, _ message: String) {
    if abs(lhs.width - rhs.width) > 0.001 || abs(lhs.height - rhs.height) > 0.001 {
        fputs("FAIL: \(message) (\(lhs) vs \(rhs))\n", stderr)
        exit(1)
    }
}

let native = CGSize(width: 3200, height: 2400)

func testSmallTileDropsToTheFloor() {
    // A 360x270pt tile at 2x backing = 720x540 px. 800x600 (native/4) covers it;
    // native/8 = 400x300 does not, so /4 is the answer.
    assertSize(
        CaptureScale.captureSize(nativePixelSize: native, presentationSize: CGSize(width: 720, height: 540)),
        CGSize(width: 800, height: 600),
        "tile at 2x"
    )
}

func testFullScreenPresentationStaysNative() {
    assertSize(
        CaptureScale.captureSize(nativePixelSize: native, presentationSize: CGSize(width: 3000, height: 2200)),
        native,
        "near-native presentation"
    )
}

func testJustOverHalfStaysNative() {
    // 1700 > 1600 (native/2), so halving would not cover it.
    assertSize(
        CaptureScale.captureSize(nativePixelSize: native, presentationSize: CGSize(width: 1700, height: 300)),
        native,
        "one axis forces native"
    )
}

func testNeverBelowMinimumWidth() {
    // A 1pt tile would want native/2048; the floor stops it at 400 wide (>= 256).
    let result = CaptureScale.captureSize(nativePixelSize: native, presentationSize: CGSize(width: 1, height: 1))
    if result.width < CaptureScale.minimumWidth {
        fputs("FAIL: went below the floor (\(result))\n", stderr)
        exit(1)
    }
    assertSize(result, CGSize(width: 400, height: 300), "clamped to floor")
}

func testDegenerateInputsFallBackToNative() {
    assertSize(
        CaptureScale.captureSize(nativePixelSize: native, presentationSize: CGSize(width: CGFloat.nan, height: 100)),
        native,
        "NaN presentation"
    )
    assertSize(
        CaptureScale.captureSize(nativePixelSize: .zero, presentationSize: CGSize(width: 100, height: 100)),
        .zero,
        "zero native"
    )
}

func testStepsAreStableAcrossAZoomSweep() {
    // Zooming smoothly must produce few distinct sizes, or every wheel notch
    // would tear down and recreate the capture stream.
    var seen = Set<String>()
    for width in stride(from: 200.0, through: 3200.0, by: 25.0) {
        let size = CaptureScale.captureSize(
            nativePixelSize: native,
            presentationSize: CGSize(width: width, height: width * 0.75)
        )
        seen.insert("\(Int(size.width))x\(Int(size.height))")
    }
    if seen.count > 5 {
        fputs("FAIL: too many distinct capture sizes across a zoom sweep: \(seen.count) \(seen.sorted())\n", stderr)
        exit(1)
    }
}

func runAllTests() {
    testSmallTileDropsToTheFloor()
    testFullScreenPresentationStaysNative()
    testJustOverHalfStaysNative()
    testNeverBelowMinimumWidth()
    testDegenerateInputsFallBackToNative()
    testStepsAreStableAcrossAZoomSweep()
    print("CaptureScale tests passed")
}

@main
struct CaptureScaleTestRunner {
    static func main() {
        runAllTests()
    }
}
