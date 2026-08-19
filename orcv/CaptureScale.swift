import CoreGraphics
import Foundation

enum CaptureScale {
    /// Native resolution divided by a power of two, so scaling stays clean and the
    /// number of distinct stream sizes is small (zooming rarely recreates a stream).
    static let minimumWidth: CGFloat = 256.0

    static func captureSize(nativePixelSize: CGSize, presentationSize: CGSize) -> CGSize {
        guard nativePixelSize.width >= 1.0, nativePixelSize.height >= 1.0 else {
            return nativePixelSize
        }
        guard presentationSize.width.isFinite, presentationSize.height.isFinite else {
            return nativePixelSize
        }

        var candidate = nativePixelSize
        while true {
            let halved = CGSize(width: candidate.width / 2.0, height: candidate.height / 2.0)
            let coversPresentation = halved.width >= presentationSize.width
                && halved.height >= presentationSize.height
            guard coversPresentation, halved.width >= minimumWidth else { break }
            candidate = halved
        }
        return CGSize(
            width: max(1.0, candidate.width.rounded()),
            height: max(1.0, candidate.height.rounded())
        )
    }
}
