import AppKit
import CoreGraphics
import Foundation

struct DisplayPanelItem {
    let workspaceID: UUID
    let title: String
    /// App running on that desktop; empty when nothing is open there.
    let subtitle: String
    let colorSeed: UInt32
    let isFocused: Bool
}

/// Floating list of the virtual desktops. Clicking a row jumps to it, double
/// clicking its name renames it in place.
final class DisplayPanelView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private var rows: [UUID: DisplayPanelRowView] = [:]

    private let rowHeight: CGFloat = 38.0
    private let maxVisibleRows: CGFloat = 12.0

    private lazy var heightConstraint: NSLayoutConstraint = {
        heightAnchor.constraint(equalToConstant: rowHeight)
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.80).cgColor
        layer?.cornerRadius = 8.0

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 2.0
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = stack

        addSubview(scrollView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 240),
            heightConstraint,
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    // The canvas below sets a crosshair; rows are clickable UI, so keep the arrow.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    func apply(items: [DisplayPanelItem]) {
        let liveIDs = Set(items.map(\.workspaceID))
        for (id, row) in rows where !liveIDs.contains(id) {
            stack.removeArrangedSubview(row)
            row.removeFromSuperview()
            rows.removeValue(forKey: id)
        }

        for (index, item) in items.enumerated() {
            let row: DisplayPanelRowView
            if let existing = rows[item.workspaceID] {
                row = existing
            } else {
                row = DisplayPanelRowView(workspaceID: item.workspaceID, height: rowHeight)
                row.onSelect = { [weak self] id in self?.onSelect?(id) }
                row.onRename = { [weak self] id, title in self?.onRename?(id, title) }
                rows[item.workspaceID] = row
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
            }
            row.apply(item: item)

            if stack.arrangedSubviews.firstIndex(of: row) != index {
                stack.removeArrangedSubview(row)
                stack.insertArrangedSubview(row, at: min(index, stack.arrangedSubviews.count))
            }
        }

        isHidden = items.isEmpty || isHiddenByUser
        let visibleRows = min(CGFloat(items.count), maxVisibleRows)
        heightConstraint.constant = max(rowHeight, visibleRows * (rowHeight + 2.0) + 12.0)
    }

    /// Tracked separately from `isHidden` so an empty desktop list can hide the
    /// panel without clobbering the user's toggle.
    var isHiddenByUser = false {
        didSet {
            guard isHiddenByUser != oldValue else { return }
            isHidden = isHiddenByUser || rows.isEmpty
        }
    }

    static func color(seed: UInt32) -> NSColor {
        // Golden-ratio hue steps keep consecutive serials far apart.
        let hue = (Double(seed) * 0.6180339887).truncatingRemainder(dividingBy: 1.0)
        return NSColor(hue: CGFloat(hue), saturation: 0.62, brightness: 0.98, alpha: 1.0)
    }
}

final class DisplayPanelRowView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?

    private let workspaceID: UUID
    private let dot = NSView()
    private let nameField = NSTextField()
    private let subtitleField = NSTextField()
    private var titleBeforeEdit = ""

    private(set) var isEditing = false

    init(workspaceID: UUID, height: CGFloat) {
        self.workspaceID = workspaceID
        super.init(frame: .zero)
        buildUI(height: height)
    }

    required init?(coder: NSCoder) {
        nil
    }

    // The orcv window is usually unfocused, so without this every row needs two clicks.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func buildUI(height: CGFloat) {
        wantsLayer = true
        layer?.cornerRadius = 5.0
        translatesAutoresizingMaskIntoConstraints = false

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4.0
        dot.translatesAutoresizingMaskIntoConstraints = false

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameField.textColor = .white
        nameField.isBordered = false
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.drawsBackground = false
        nameField.lineBreakMode = .byTruncatingTail
        nameField.delegate = self
        nameField.focusRingType = .none

        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.isBordered = false
        subtitleField.isEditable = false
        subtitleField.isSelectable = false
        subtitleField.drawsBackground = false
        subtitleField.lineBreakMode = .byTruncatingTail

        addSubview(dot)
        addSubview(nameField)
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),

            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            nameField.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameField.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            subtitleField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            subtitleField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 0),
        ])
    }

    func apply(item: DisplayPanelItem) {
        dot.layer?.backgroundColor = DisplayPanelView.color(seed: item.colorSeed).cgColor
        // Never clobber text the user is typing.
        if nameField.currentEditor() == nil {
            nameField.stringValue = item.title
        }
        subtitleField.stringValue = item.subtitle.isEmpty ? "\u{2014}" : item.subtitle
        layer?.backgroundColor = item.isFocused
            ? NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
            : NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, nameField.frame.contains(point) {
            beginRename()
            return
        }
        onSelect?(workspaceID)
    }

    private func beginRename() {
        guard !isEditing else { return }
        titleBeforeEdit = nameField.stringValue
        isEditing = true
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.drawsBackground = true
        nameField.backgroundColor = .textBackgroundColor
        nameField.textColor = .textColor
        window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    private func endRename(commit: Bool) {
        guard isEditing else { return }
        isEditing = false
        let value = nameField.stringValue
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.drawsBackground = false
        nameField.textColor = .white
        if commit {
            onRename?(workspaceID, value)
        } else {
            nameField.stringValue = titleBeforeEdit
        }
    }
}

extension DisplayPanelRowView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        endRename(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        endRename(commit: false)
        window?.makeFirstResponder(nil)
        return true
    }
}
