import AppKit
import SwiftUI

/// Borderless panels rely on `isMovableByWindowBackground`; when SwiftUI returns `nil` from hit-testing
/// (e.g. `allowsHitTesting(false)`), the next responder is often this content view — it must be movable.
final class MovableVisualEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

// MARK: - Title bar drag strip

/// Full-width top strip — explicit drag because `isMovableByWindowBackground` / `mouseDownCanMoveWindow`
/// do not reliably move `NSPanel` + borderless + SwiftUI (`nonactivatingPanel` makes this worse).
private final class TitleBarDragNSView: NSView {
    private enum Dots {
        static let spacing: CGFloat = 5
        static let diameter: CGFloat = 1.75
        static let alpha: CGFloat = 0.11
    }

    /// Keeps `MenuBarHostingView.hitTest` from dropping this view through to the blur (which would steal clicks).
    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }

    private var handCursorTracking: NSTrackingArea?
    private var dragMouseScreenStart = CGPoint.zero
    private var dragWindowFrameStart = NSRect.zero

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        dragMouseScreenStart = NSEvent.mouseLocation
        dragWindowFrameStart = win.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragMouseScreenStart.x
        let dy = now.y - dragMouseScreenStart.y
        win.setFrameOrigin(NSPoint(x: dragWindowFrameStart.origin.x + dx, y: dragWindowFrameStart.origin.y + dy))
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        guard b.width > 0.5, b.height > 0.5 else { return }

        ctx.saveGState()
        ctx.clip(to: dirtyRect)

        let fill = NSColor.white.withAlphaComponent(Dots.alpha).cgColor
        ctx.setFillColor(fill)

        let s = Dots.spacing
        let d = Dots.diameter
        var row = 0
        var y: CGFloat = s * 0.35
        while y < b.height + d {
            let stagger = (row % 2 == 0) ? CGFloat(0) : s * 0.5
            var x = s * 0.35 + stagger
            while x < b.width + d {
                let dot = CGRect(x: x, y: y, width: d, height: d)
                if dot.intersects(dirtyRect) {
                    ctx.fillEllipse(in: dot)
                }
                x += s
            }
            y += s
            row += 1
        }

        ctx.restoreGState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = handCursorTracking { removeTrackingArea(t) }
        guard bounds.width > 0.5, bounds.height > 0.5 else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        handCursorTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.openHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.pop()
    }
}

struct WindowTitleBarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TitleBarDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
