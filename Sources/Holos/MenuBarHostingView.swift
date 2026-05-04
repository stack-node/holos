import AppKit
import SwiftUI

/// SwiftUI’s root `NSHostingView` does not participate in `isMovableByWindowBackground` unless this is true.
/// Leaf views under the hosting surface still receive hits first; we pass non-interactive hits through so
/// `MovableVisualEffectView` (or other movable ancestors) can handle window drags.
final class MenuBarHostingView: NSHostingView<MenuBarView> {
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === self { return self }
        if hit.mouseDownCanMoveWindow { return hit }
        guard window?.isMovableByWindowBackground == true else { return hit }

        // Scroll views (and their clip/document hierarchy) need real hits for scrolling.
        var v: NSView? = hit
        while let cur = v {
            if cur is NSScrollView { return hit }
            v = cur.superview
        }

        v = hit
        while let cur = v, cur !== self {
            if cur is NSControl { return hit }
            if cur is NSTextView { return hit }
            v = cur.superview
        }

        return nil
    }
}
