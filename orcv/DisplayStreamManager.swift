import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import IOSurface
import ScreenCaptureKit

/// Captures each display through ScreenCaptureKit and hands out the latest IOSurface
/// per display, ready to be assigned to a CALayer's contents.
///
/// Two properties of SCStream shape this design:
/// - The configuration carries `width`/`height`, so the compositor does the downscale
///   and we never move more pixels than the canvas draws.
/// - `updateConfiguration` changes size and frame rate in place, so a zoom or an fps
///   change no longer tears the stream down and leaves a gap in the picture.
final class DisplayStreamManager {
    var onFrame: (() -> Void)?
    var onDisplayFrame: ((CGDirectDisplayID, IOSurface) -> Void)?
    var onError: ((String) -> Void)?

    private let controller: CaptureController
    private let surfaceStore = SurfaceStore()

    init() {
        controller = CaptureController(surfaceStore: surfaceStore)
        controller.onFrame = { [weak self] displayID, surface in
            guard let self else { return }
            DispatchQueue.main.async {
                self.onDisplayFrame?(displayID, surface)
                self.onFrame?()
            }
        }
        controller.onError = { [weak self] message in
            self?.onError?(message)
        }
    }

    func stopAll() {
        controller.stopAll()
    }

    func configureStreams(for descriptors: [DisplayDescriptor]) {
        controller.configure(descriptors: descriptors)
    }

    func latestSurface(for displayID: CGDirectDisplayID) -> IOSurface? {
        surfaceStore.surface(for: displayID)
    }
}

/// Readable from the main thread on every layout pass, written from the capture queue.
/// Unchecked because every access goes through `queue`.
private final class SurfaceStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "today.jason.orcv.surface-store", attributes: .concurrent)
    private var surfaces: [CGDirectDisplayID: IOSurface] = [:]

    func surface(for displayID: CGDirectDisplayID) -> IOSurface? {
        queue.sync { surfaces[displayID] }
    }

    func store(_ surface: IOSurface, for displayID: CGDirectDisplayID) {
        queue.async(flags: .barrier) { self.surfaces[displayID] = surface }
    }

    func remove(_ displayID: CGDirectDisplayID) {
        queue.async(flags: .barrier) { self.surfaces.removeValue(forKey: displayID) }
    }

    func removeAll() {
        queue.async(flags: .barrier) { self.surfaces.removeAll() }
    }
}

/// Serializes every mutation of the stream set. Enumerating shareable content is slow
/// (seconds, measured), so the display catalog is cached and only refreshed when a
/// requested display is missing from it.
/// Unchecked because every mutation of its state goes through the serial `queue`.
private final class CaptureController: @unchecked Sendable {
    private struct Entry {
        let stream: SCStream
        let output: FrameCollector
        var width: Int
        var height: Int
        var fps: Double
    }

    var onFrame: ((CGDirectDisplayID, IOSurface) -> Void)?
    var onError: ((String) -> Void)?

    private let surfaceStore: SurfaceStore
    private let queue = DispatchQueue(label: "today.jason.orcv.stream-control")
    private let sampleQueue = DispatchQueue(label: "today.jason.orcv.stream-callback", qos: .userInteractive)

    private var entries: [CGDirectDisplayID: Entry] = [:]
    private var displayCatalog: [CGDirectDisplayID: SCDisplay] = [:]
    private var latestDescriptors: [CGDirectDisplayID: DisplayDescriptor] = [:]
    private var reportedErrors = Set<String>()
    private var isApplying = false
    private var isDirty = false

    init(surfaceStore: SurfaceStore) {
        self.surfaceStore = surfaceStore
    }

    func configure(descriptors: [DisplayDescriptor]) {
        queue.async { [weak self] in
            guard let self else { return }
            var unique: [CGDirectDisplayID: DisplayDescriptor] = [:]
            for descriptor in descriptors where unique[descriptor.displayID] == nil {
                unique[descriptor.displayID] = descriptor
            }
            self.latestDescriptors = unique
            self.isDirty = true
            self.pumpOnQueue()
        }
    }

    func stopAll() {
        queue.async { [weak self] in
            guard let self else { return }
            self.latestDescriptors = [:]
            self.isDirty = false
            let streams = self.entries.values.map(\.stream)
            self.entries.removeAll()
            self.surfaceStore.removeAll()
            Task {
                for stream in streams {
                    try? await stream.stopCapture()
                }
            }
        }
    }

    /// One apply in flight at a time. Anything that arrives while it runs sets the
    /// dirty flag, so the newest descriptors always get applied exactly once more.
    /// Must be called on `queue`.
    private func pumpOnQueue() {
        guard !isApplying, isDirty else { return }
        isApplying = true
        isDirty = false
        Task { [weak self] in
            guard let self else { return }
            await self.apply()
            self.queue.async {
                self.isApplying = false
                self.pumpOnQueue()
            }
        }
    }

    private func snapshot() -> [CGDirectDisplayID: DisplayDescriptor] {
        queue.sync { latestDescriptors }
    }

    private func apply() async {
        let descriptors = snapshot()

        for displayID in queue.sync(execute: { Array(entries.keys) }) {
            guard let descriptor = descriptors[displayID] else {
                await teardown(displayID: displayID, keepLastFrame: false)
                continue
            }
            if descriptor.maxFPS <= 0.0 {
                // Off-screen: release the stream but keep the last frame on the tile.
                await teardown(displayID: displayID, keepLastFrame: true)
            }
        }

        for (displayID, descriptor) in descriptors where descriptor.maxFPS > 0.0 {
            let width = Int(max(1.0, descriptor.captureSize.width.rounded()))
            let height = Int(max(1.0, descriptor.captureSize.height.rounded()))

            if let entry = queue.sync(execute: { entries[displayID] }) {
                let sameSize = entry.width == width && entry.height == height
                let sameFPS = abs(entry.fps - descriptor.maxFPS) <= 0.0001
                if sameSize, sameFPS { continue }
                if await update(displayID: displayID, entry: entry, width: width, height: height, fps: descriptor.maxFPS) {
                    continue
                }
                await teardown(displayID: displayID, keepLastFrame: true)
            }

            await start(displayID: displayID, width: width, height: height, fps: descriptor.maxFPS)
        }
    }

    private func update(displayID: CGDirectDisplayID, entry: Entry, width: Int, height: Int, fps: Double) async -> Bool {
        guard #available(macOS 14.0, *) else { return false }
        do {
            try await entry.stream.updateConfiguration(
                Self.configuration(width: width, height: height, fps: fps)
            )
            queue.sync {
                if var stored = entries[displayID] {
                    stored.width = width
                    stored.height = height
                    stored.fps = fps
                    entries[displayID] = stored
                }
            }
            return true
        } catch {
            return false
        }
    }

    private func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Double) async {
        guard let display = await resolveDisplay(displayID) else {
            report("Display \(displayID) is not available for capture")
            return
        }

        let output = FrameCollector { [weak self] surface in
            guard let self else { return }
            self.surfaceStore.store(surface, for: displayID)
            self.onFrame?(displayID, surface)
        }
        let stream = SCStream(
            filter: SCContentFilter(display: display, excludingWindows: []),
            configuration: Self.configuration(width: width, height: height, fps: fps),
            delegate: nil
        )

        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            report("Capture failed for display \(displayID): \(error.localizedDescription)")
            return
        }

        var stale = false
        queue.sync {
            guard let descriptor = latestDescriptors[displayID], descriptor.maxFPS > 0.0 else {
                stale = true
                return
            }
            entries[displayID] = Entry(stream: stream, output: output, width: width, height: height, fps: fps)
        }
        if stale {
            try? await stream.stopCapture()
        }
    }

    private func teardown(displayID: CGDirectDisplayID, keepLastFrame: Bool) async {
        let entry: Entry? = queue.sync { entries.removeValue(forKey: displayID) }
        guard let entry else { return }
        if !keepLastFrame {
            surfaceStore.remove(displayID)
        }
        try? await entry.stream.stopCapture()
    }

    /// Cached: SCShareableContent enumeration was measured taking seconds.
    private func resolveDisplay(_ displayID: CGDirectDisplayID) async -> SCDisplay? {
        if let cached = queue.sync(execute: { displayCatalog[displayID] }) {
            return cached
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            queue.sync {
                displayCatalog = Dictionary(
                    content.displays.map { ($0.displayID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        } catch {
            report("Screen capture unavailable: \(error.localizedDescription)")
            return nil
        }
        return queue.sync { displayCatalog[displayID] }
    }

    private func report(_ message: String) {
        // Same message repeats every refresh otherwise.
        let isNew: Bool = queue.sync { reportedErrors.insert(message).inserted }
        guard isNew else { return }
        onError?(message)
    }

    private static func configuration(width: Int, height: Int, fps: Double) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        // Keep the system default depth: we retain the latest surface to hold the last
        // frame of paused tiles, and a shallow pool risks it being recycled underneath us.
        config.queueDepth = 3
        config.capturesAudio = false
        config.scalesToFit = false
        let safeFPS = min(120.0, max(1.0, fps.isFinite ? fps : 60.0))
        config.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(safeFPS.rounded())
        )
        return config
    }
}

private final class FrameCollector: NSObject, SCStreamOutput {
    private let onSurface: (IOSurface) -> Void

    init(onSurface: @escaping (IOSurface) -> Void) {
        self.onSurface = onSurface
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer) else { return }
        onSurface(surfaceRef.takeUnretainedValue())
    }
}
