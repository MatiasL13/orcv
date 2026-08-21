import CoreGraphics
import Foundation

enum DisplayArrangement {
    /// macOS puts the menu bar and the Dock on whichever display sits at the global
    /// origin. A freshly created virtual display can land there and steal them, and
    /// because the arrangement anchors to the virtual displays' own current bounds,
    /// that position then perpetuates itself.
    ///
    /// Shifts the whole virtual block, preserving relative positions (the canvas
    /// pointer mapping depends on those), so it clears the main display's rect.
    static func shiftClearingMainDisplay(
        origins: [CGDirectDisplayID: CGPoint],
        sizes: [CGDirectDisplayID: CGSize],
        mainDisplayRect: CGRect
    ) -> [CGDirectDisplayID: CGPoint] {
        guard !origins.isEmpty, mainDisplayRect.width > 1, mainDisplayRect.height > 1 else {
            return origins
        }

        let rects: [CGRect] = origins.compactMap { displayID, origin in
            guard let size = sizes[displayID], size.width > 1, size.height > 1 else { return nil }
            return CGRect(origin: origin, size: size)
        }
        guard !rects.isEmpty else { return origins }
        guard rects.contains(where: { $0.intersects(mainDisplayRect) }) else { return origins }

        // Park the block directly above the main display.
        let blockMaxY = rects.map(\.maxY).max() ?? 0
        let shiftY = mainDisplayRect.minY - blockMaxY
        guard shiftY.isFinite, shiftY < 0 else { return origins }

        return origins.mapValues { CGPoint(x: $0.x, y: ($0.y + shiftY).rounded()) }
    }
}
