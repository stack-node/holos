import AppKit
import SwiftUI

/// SwiftUI's `.scrollIndicators(.hidden)` does not always remove AppKit's vertical scroller thumb.
/// Attach as a background inside the scroll content area so the view hierarchy reaches the enclosing `NSScrollView`.
struct VerticalScrollBarSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var node: NSView? = nsView.superview
            while let cur = node {
                if let scroll = cur as? NSScrollView {
                    scroll.hasVerticalScroller = false
                    scroll.autohidesScrollers = true
                    break
                }
                node = cur.superview
            }
        }
    }
}

// MARK: - Sidebar scroll metrics (macOS)

/// Hides the vertical scroller and publishes clip offsets from `NSScrollView`.
/// SwiftUI `PreferenceKey` / coordinate-space tracking often misses scroll deltas during scrolling.
struct MacScrollViewChrome: NSViewRepresentable {
    @Binding var clipOffsetY: CGFloat
    @Binding var maxClipOffsetY: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(clipOffsetY: $clipOffsetY, maxClipOffsetY: $maxClipOffsetY)
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        context.coordinator.attach(to: v)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.syncPublish(from: nsView) // layout / window resize — not always paired with clip bounds notifications
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        private var clipOffsetY: Binding<CGFloat>
        private var maxClipOffsetY: Binding<CGFloat>
        private weak var observedScrollView: NSScrollView?
        private weak var observedDocumentView: NSView?
        private var clipScrollObservationTokens: [NSObjectProtocol] = []
        private var documentFrameObservationToken: NSObjectProtocol?

        init(clipOffsetY: Binding<CGFloat>, maxClipOffsetY: Binding<CGFloat>) {
            self.clipOffsetY = clipOffsetY
            self.maxClipOffsetY = maxClipOffsetY
        }

        /// Host view may not be under `NSScrollView` on first `makeNSView`; retry next tick.
        func attach(to view: NSView) {
            guard findScrollView(from: view) == nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.syncPublish(from: view)
            }
        }

        /// SwiftUI calls `updateNSView` on layout — window resize does not always fire clip-view bounds notifications with distinct scroll deltas.
        func syncPublish(from hostingAnchor: NSView) {
            guard let scroll = findScrollView(from: hostingAnchor) else { return }
            setupObservationsIfNeeded(scroll)
            updateDocumentFrameObservation(scroll)
            publish(scroll)
        }

        private func findScrollView(from view: NSView) -> NSScrollView? {
            var node: NSView? = view.superview
            while let cur = node {
                if let scroll = cur as? NSScrollView { return scroll }
                node = cur.superview
            }
            return nil
        }

        private func setupObservationsIfNeeded(_ scroll: NSScrollView) {
            guard observedScrollView !== scroll else { return }

            removeAllObservers()
            observedScrollView = scroll
            scroll.hasVerticalScroller = false
            scroll.autohidesScrollers = true
            scroll.postsFrameChangedNotifications = true
            scroll.contentView.postsBoundsChangedNotifications = true
            scroll.contentView.postsFrameChangedNotifications = true

            appendClipScrollObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView) { [weak self] in
                guard let self, let s = self.observedScrollView else { return }
                self.publish(s)
            }
            appendClipScrollObserver(forName: NSView.frameDidChangeNotification, object: scroll) { [weak self] in
                guard let self, let s = self.observedScrollView else { return }
                self.publish(s)
            }
        }

        private func updateDocumentFrameObservation(_ scroll: NSScrollView) {
            guard let doc = scroll.documentView else {
                removeDocumentFrameObserver()
                return
            }
            guard observedDocumentView !== doc else { return }

            removeDocumentFrameObserver()
            observedDocumentView = doc
            doc.postsFrameChangedNotifications = true
            documentFrameObservationToken = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: doc,
                queue: .main
            ) { [weak self] _ in
                guard let self, let s = self.observedScrollView else { return }
                self.publish(s)
            }
        }

        private func appendClipScrollObserver(forName name: Notification.Name, object: AnyObject?, handler: @escaping () -> Void) {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { _ in handler() }
            clipScrollObservationTokens.append(token)
        }

        private func removeDocumentFrameObserver() {
            if let t = documentFrameObservationToken {
                NotificationCenter.default.removeObserver(t)
                documentFrameObservationToken = nil
            }
            observedDocumentView = nil
        }

        private func removeAllObservers() {
            for t in clipScrollObservationTokens {
                NotificationCenter.default.removeObserver(t)
            }
            clipScrollObservationTokens.removeAll()
            removeDocumentFrameObserver()
            observedScrollView = nil
        }

        private func publish(_ scroll: NSScrollView) {
            updateDocumentFrameObservation(scroll)
            let docH = scroll.documentView?.bounds.height ?? 0
            let visibleH = scroll.contentView.bounds.height
            let maxO = max(0, docH - visibleH)
            let y = scroll.contentView.bounds.origin.y
            clipOffsetY.wrappedValue = y
            maxClipOffsetY.wrappedValue = maxO
        }

        func teardown() {
            removeAllObservers()
        }

        deinit {
            teardown()
        }
    }
}
