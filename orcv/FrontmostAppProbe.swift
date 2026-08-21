import CoreGraphics
import Foundation

/// Resolves which application owns the frontmost window on each display, so the
/// displays panel can label every virtual desktop with what is running on it.
enum FrontmostAppProbe {
    /// Minimum fraction of the display a window must cover to count as "the app on
    /// this desktop". Apps publish thin auxiliary windows (title bars, 32-44pt tall)
    /// that sit in front of the real window in the window list.
    private static let minimumCoverage: CGFloat = 0.2

    /// `windows` must come from `CGWindowListCopyWindowInfo`, which returns windows
    /// front to back. Pure so it can be tested without a window server.
    static func ownerName(in displayBounds: CGRect, windows: [[String: Any]], excludingPID: pid_t = 0) -> String? {
        let displayArea = displayBounds.width * displayBounds.height
        guard displayArea > 0 else { return nil }

        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
            if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0.0 { continue }
            if excludingPID != 0, (window[kCGWindowOwnerPID as String] as? pid_t) == excludingPID { continue }
            guard let owner = window[kCGWindowOwnerName as String] as? String, !owner.isEmpty else { continue }
            guard let boundsDict = window[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary) else { continue }

            // Windows can straddle two displays, so match on the center point.
            guard displayBounds.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            guard (frame.width * frame.height) / displayArea >= minimumCoverage else { continue }
            return owner
        }
        return nil
    }

    /// One window-list snapshot for every display. `kCGWindowOwnerName` needs no
    /// permission; `kCGWindowName` would require screen recording, so it is unused.
    static func ownerNamesByDisplayID(_ displayIDs: [CGDirectDisplayID]) -> [CGDirectDisplayID: String] {
        guard !displayIDs.isEmpty else { return [:] }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        let selfPID = getpid()
        var result: [CGDirectDisplayID: String] = [:]
        for displayID in displayIDs {
            if let owner = ownerName(in: CGDisplayBounds(displayID), windows: windows, excludingPID: selfPID) {
                result[displayID] = owner
            }
        }
        return result
    }
}
