import AppKit

// MARK: - Layout / geometry

private enum MainWindowResizeLayout {
    static let preferredMargin: CGFloat = 16

    static func effectiveMargin(width w: CGFloat, height h: CGFloat) -> CGFloat {
        let cap = max(4, min(w, h) / 2 - 2)
        var m = min(preferredMargin, cap)
        m = min(m, max(2, w / 2 - 1), max(2, h / 2 - 1))
        return m
    }

    /// Non-flipped local rects (origin bottom-left) for each resize zone. No full-width top strip — leaves top-center for window drag.
    static func frames(in b: NSRect, margin m: CGFloat) -> [MainWindowResizeHandleView.Region: NSRect] {
        let w = b.width, h = b.height
        guard w > 2 * m + 1, h > 2 * m + 1 else { return [:] }
        var map: [MainWindowResizeHandleView.Region: NSRect] = [:]
        map[.topLeft] = NSRect(x: 0, y: h - m, width: m, height: m)
        map[.topRight] = NSRect(x: w - m, y: h - m, width: m, height: m)
        map[.bottomLeft] = NSRect(x: 0, y: 0, width: m, height: m)
        map[.bottomRight] = NSRect(x: w - m, y: 0, width: m, height: m)
        map[.left] = NSRect(x: 0, y: m, width: m, height: h - 2 * m)
        map[.right] = NSRect(x: w - m, y: m, width: m, height: h - 2 * m)
        map[.bottom] = NSRect(x: m, y: 0, width: w - 2 * m, height: m)
        return map
    }

    static func newFrame(
        for r: MainWindowResizeHandleView.Region,
        start sf: NSRect,
        dx: CGFloat,
        dy: CGFloat,
        minW: CGFloat,
        minH: CGFloat,
        maxW: CGFloat,
        maxH: CGFloat
    ) -> NSRect {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }

        var x = sf.minX, y = sf.minY, w = sf.width, h = sf.height

        switch r {
        case .right:
            w = clamp(sf.width + dx, minW, maxW)
            x = sf.minX
            y = sf.minY
            h = sf.height
        case .left:
            w = clamp(sf.width - dx, minW, maxW)
            x = sf.maxX - w
            y = sf.minY
            h = sf.height
        case .bottom:
            h = clamp(sf.height - dy, minH, maxH)
            x = sf.minX
            y = sf.maxY - h
            w = sf.width
        case .topRight:
            w = clamp(sf.width + dx, minW, maxW)
            h = clamp(sf.height + dy, minH, maxH)
            x = sf.minX
            y = sf.minY
        case .topLeft:
            w = clamp(sf.width - dx, minW, maxW)
            h = clamp(sf.height + dy, minH, maxH)
            x = sf.maxX - w
            y = sf.minY
        case .bottomRight:
            w = clamp(sf.width + dx, minW, maxW)
            h = clamp(sf.height - dy, minH, maxH)
            x = sf.minX
            y = sf.maxY - h
        case .bottomLeft:
            w = clamp(sf.width - dx, minW, maxW)
            h = clamp(sf.height - dy, minH, maxH)
            x = sf.maxX - w
            y = sf.maxY - h
        }

        return NSRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Edge handle (physical strip / corner — default hit testing)

private final class MainWindowResizeHandleView: NSView {
    enum Region: Equatable, Hashable {
        case topLeft, topRight, bottomLeft, bottomRight
        case bottom, left, right
    }

    fileprivate let region: Region
    private var dragStartScreen: CGPoint = .zero
    private var dragStartFrame: NSRect = .zero
    private var trackingArea: NSTrackingArea?

    init(region: Region) {
        self.region = region
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingArea.map { removeTrackingArea($0) }
        guard bounds.width > 0.5, bounds.height > 0.5 else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(for: region).set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(for: region).set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private func cursor(for r: Region) -> NSCursor {
        switch r {
        case .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        dragStartScreen = NSEvent.mouseLocation
        dragStartFrame = win.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartScreen.x
        let dy = now.y - dragStartScreen.y
        let sf = dragStartFrame
        let minW = win.minSize.width
        let minH = win.minSize.height
        let rawMaxW = win.maxSize.width
        let rawMaxH = win.maxSize.height
        let maxW = rawMaxW.isFinite && rawMaxW >= minW ? rawMaxW : CGFloat.greatestFiniteMagnitude
        let maxH = rawMaxH.isFinite && rawMaxH >= minH ? rawMaxH : CGFloat.greatestFiniteMagnitude

        let newFrame = MainWindowResizeLayout.newFrame(
            for: region, start: sf, dx: dx, dy: dy, minW: minW, minH: minH, maxW: maxW, maxH: maxH
        )
        win.setFrame(newFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {}
}

// MARK: - Full-size chrome (only edge subviews receive hits)

/// Transparent overlay: **strip/corner subviews** sit on top for resize; gaps are not covered by any subview,
/// so hits reach the SwiftUI `NSHostingView` below and `isMovableByWindowBackground` works.
final class MainWindowResizeChromeView: NSView {
    private let handles: [MainWindowResizeHandleView]

    override init(frame frameRect: NSRect) {
        let regions: [MainWindowResizeHandleView.Region] = [
            .topLeft, .topRight, .bottomLeft, .bottomRight, .left, .right, .bottom,
        ]
        self.handles = regions.map { MainWindowResizeHandleView(region: $0) }
        super.init(frame: frameRect)
        for h in handles {
            h.autoresizingMask = []
            addSubview(h)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard window?.styleMask.contains(.resizable) == true else { return nil }
        let hit = super.hitTest(point)
        if hit === self { return nil }
        return hit
    }

    override func layout() {
        super.layout()
        let b = bounds
        let m = MainWindowResizeLayout.effectiveMargin(width: b.width, height: b.height)
        let frames = MainWindowResizeLayout.frames(in: b, margin: m)
        for h in handles {
            h.frame = frames[h.region] ?? .zero
        }
    }
}
