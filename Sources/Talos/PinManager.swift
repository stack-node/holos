import AppKit
import SwiftUI
import Combine

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PinManager: ObservableObject {
    static let shared = PinManager()
    private init() {}

    @Published private(set) var isShowing = false
    @Published var isSticky = false

    private var panel: NSPanel?
    private var blurView: NSVisualEffectView?
    private var cancellables = Set<AnyCancellable>()

    func toggle(near buttonRect: NSRect) {
        if isShowing && !isSticky {
            hide()
        } else {
            show(near: buttonRect)
        }
    }

    func show(near buttonRect: NSRect) {
        if let p = panel, p.isVisible {
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isShowing = true
            return
        }

        let width: CGFloat  = 380
        let height: CGFloat = 500
        let gap: CGFloat    = 6

        var x = buttonRect.midX - width / 2
        var y = buttonRect.minY - height - gap
        if let screen = NSScreen.main {
            x = max(screen.visibleFrame.minX + 4, min(x, screen.visibleFrame.maxX - width - 4))
            y = max(screen.visibleFrame.minY + 4, y)
        }

        let p = KeyablePanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isMovable = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.minSize = NSSize(width: 320, height: 380)

        let config = TalosConfig.shared
        let blur = NSVisualEffectView()
        blur.material = config.blurMaterial
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blurView = blur

        let hosting = NSHostingView(rootView: MenuBarView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
        ])
        p.contentView = blur

        // Observe blur config changes
        config.$blurStrength
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.blurView?.material = TalosConfig.shared.blurMaterial
            }
            .store(in: &cancellables)

        config.$blurEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.blurView?.blendingMode = enabled ? .behindWindow : .withinWindow
            }
            .store(in: &cancellables)

        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p
        isShowing = true
    }

    func hide() {
        panel?.orderOut(nil)
        isShowing = false
    }
}
