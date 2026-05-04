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
