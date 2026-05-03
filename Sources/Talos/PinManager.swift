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
    @Published var isMinimal = false {
        didSet { applyMinimalResize() }
    }
    @Published private(set) var isSidebarOpen = false
    @Published private(set) var isRightSidebarOpen = false

    private var panel: NSPanel?
    private var sidebarPanel: NSPanel?
    private var rightSidebarPanel: NSPanel?
    private var blurView: NSVisualEffectView?
    private var sidebarBlurView: NSVisualEffectView?
    private var rightSidebarBlurView: NSVisualEffectView?
    private var cancellables = Set<AnyCancellable>()
    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var rightResizeObserver: NSObjectProtocol?
    private var rightMoveObserver: NSObjectProtocol?

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
        p.minSize = NSSize(width: 240, height: 240)

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
        hideSidebar()
        hideRightSidebar()
        panel?.orderOut(nil)
        isShowing = false
    }

    // MARK: - Sidebar

    private let sidebarW: CGFloat       = 200
    private(set) var rightSidebarW: CGFloat = 340
    private let sidebarGap: CGFloat     = 0    // flush with main window
    private let sidebarInset: CGFloat   = 14  // sidebar shorter top+bottom
    private let rightSidebarMinW: CGFloat = 200
    private let rightSidebarMaxW: CGFloat = 700

    func toggleSidebar() {
        isSidebarOpen ? hideSidebar() : showSidebar()
    }

    func toggleRightSidebar() {
        isRightSidebarOpen ? hideRightSidebar() : showRightSidebar()
    }

    func resizeRightSidebar(to width: CGFloat) {
        guard let main = panel, let sp = rightSidebarPanel else { return }
        rightSidebarW = min(rightSidebarMaxW, max(rightSidebarMinW, width))
        let frame = NSRect(
            x: main.frame.maxX + sidebarGap,
            y: sp.frame.minY,
            width: rightSidebarW,
            height: sp.frame.height
        )
        sp.setFrame(frame, display: true)
    }

    private func sidebarFrame(for mainFrame: NSRect) -> NSRect {
        NSRect(
            x: mainFrame.minX - sidebarW - sidebarGap,
            y: mainFrame.minY + sidebarInset,
            width: sidebarW,
            height: mainFrame.height - sidebarInset * 2
        )
    }

    private func showSidebar() {
        guard let main = panel, main.isVisible else { return }

        if sidebarPanel == nil {
            let sp = KeyablePanel(
                contentRect: sidebarFrame(for: main.frame),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            sp.isMovable = false
            sp.hidesOnDeactivate = false
            sp.isReleasedWhenClosed = false
            sp.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            sp.isOpaque = false
            sp.backgroundColor = .clear

            let config = TalosConfig.shared
            let blur = NSVisualEffectView()
            blur.material = config.blurMaterial
            blur.blendingMode = config.blurEnabled ? .behindWindow : .withinWindow
            blur.state = .active
            blur.appearance = NSAppearance(named: .vibrantDark)
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 12
            blur.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            blur.layer?.masksToBounds = true
            sidebarBlurView = blur

            config.$blurStrength
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.sidebarBlurView?.material = TalosConfig.shared.blurMaterial }
                .store(in: &cancellables)
            config.$blurEnabled
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enabled in self?.sidebarBlurView?.blendingMode = enabled ? .behindWindow : .withinWindow }
                .store(in: &cancellables)

            let hosting = NSHostingView(rootView: SidebarContentView())
            hosting.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: blur.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            ])
            sp.contentView = blur
            sidebarPanel = sp
        }

        guard let sp = sidebarPanel else { return }

        let target = sidebarFrame(for: main.frame)
        let start  = NSRect(x: main.frame.minX - sidebarGap, y: target.minY,
                            width: sidebarW, height: target.height)

        sp.setFrame(start, display: false)
        sp.alphaValue = 0
        // Child window follows parent automatically with zero lag; ordered below = under main
        main.addChildWindow(sp, ordered: .below)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            sp.animator().setFrame(target, display: true)
            sp.animator().alphaValue = 1
        }

        let reframeSidebar = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let main = self.panel, let sp = self.sidebarPanel else { return }
                sp.setFrame(self.sidebarFrame(for: main.frame), display: true)
            }
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: main, queue: .main) { _ in reframeSidebar() }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: main, queue: .main) { _ in reframeSidebar() }

        isSidebarOpen = true
    }

    private func hideSidebar() {
        guard let sp = sidebarPanel, let main = panel else {
            isSidebarOpen = false
            return
        }

        resizeObserver.map { NotificationCenter.default.removeObserver($0) }
        resizeObserver = nil
        moveObserver.map { NotificationCenter.default.removeObserver($0) }
        moveObserver = nil

        let endFrame = NSRect(x: main.frame.minX - sidebarGap, y: sp.frame.minY,
                              width: sp.frame.width, height: sp.frame.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            sp.animator().setFrame(endFrame, display: true)
            sp.animator().alphaValue = 0
        }, completionHandler: {
            main.removeChildWindow(sp)
            sp.orderOut(nil)
        })

        isSidebarOpen = false
    }

    private func rightSidebarFrame(for mainFrame: NSRect) -> NSRect {
        NSRect(
            x: mainFrame.maxX + sidebarGap,
            y: mainFrame.minY + sidebarInset,
            width: rightSidebarW,
            height: mainFrame.height - sidebarInset * 2
        )
    }

    private func showRightSidebar() {
        guard let main = panel, main.isVisible else { return }

        if rightSidebarPanel == nil {
            let sp = KeyablePanel(
                contentRect: rightSidebarFrame(for: main.frame),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            sp.isMovable = false
            sp.hidesOnDeactivate = false
            sp.isReleasedWhenClosed = false
            sp.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            sp.isOpaque = false
            sp.backgroundColor = .clear

            let config = TalosConfig.shared
            let blur = NSVisualEffectView()
            blur.material = config.blurMaterial
            blur.blendingMode = config.blurEnabled ? .behindWindow : .withinWindow
            blur.state = .active
            blur.appearance = NSAppearance(named: .vibrantDark)
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 12
            blur.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            blur.layer?.masksToBounds = true
            rightSidebarBlurView = blur

            config.$blurStrength
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.rightSidebarBlurView?.material = TalosConfig.shared.blurMaterial }
                .store(in: &cancellables)
            config.$blurEnabled
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enabled in self?.rightSidebarBlurView?.blendingMode = enabled ? .behindWindow : .withinWindow }
                .store(in: &cancellables)

            let hosting = NSHostingView(rootView: RightSidebarContentView())
            hosting.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: blur.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            ])
            sp.contentView = blur
            rightSidebarPanel = sp
        }

        guard let sp = rightSidebarPanel else { return }

        let target = rightSidebarFrame(for: main.frame)
        let start  = NSRect(x: main.frame.maxX + sidebarGap, y: target.minY,
                            width: rightSidebarW, height: target.height)

        sp.setFrame(start, display: false)
        sp.alphaValue = 0
        main.addChildWindow(sp, ordered: .below)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            sp.animator().setFrame(target, display: true)
            sp.animator().alphaValue = 1
        }

        let reframeRight = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let main = self.panel, let sp = self.rightSidebarPanel else { return }
                sp.setFrame(NSRect(
                    x: main.frame.maxX + self.sidebarGap,
                    y: main.frame.minY + self.sidebarInset,
                    width: sp.frame.width,
                    height: main.frame.height - self.sidebarInset * 2
                ), display: true)
                self.rightSidebarW = sp.frame.width
            }
        }
        rightResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: main, queue: .main) { _ in reframeRight() }
        rightMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: main, queue: .main) { _ in reframeRight() }

        isRightSidebarOpen = true
    }

    private func hideRightSidebar() {
        guard let sp = rightSidebarPanel, let main = panel else {
            isRightSidebarOpen = false
            return
        }

        rightResizeObserver.map { NotificationCenter.default.removeObserver($0) }
        rightResizeObserver = nil
        rightMoveObserver.map { NotificationCenter.default.removeObserver($0) }
        rightMoveObserver = nil

        let endFrame = NSRect(x: main.frame.maxX + rightSidebarW + sidebarGap, y: sp.frame.minY,
                              width: rightSidebarW, height: sp.frame.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            sp.animator().setFrame(endFrame, display: true)
            sp.animator().alphaValue = 0
        }, completionHandler: {
            main.removeChildWindow(sp)
            sp.orderOut(nil)
        })

        isRightSidebarOpen = false
    }

    private func applyMinimalResize() {
        guard let p = panel, p.isVisible else { return }
        let targetH: CGFloat = isMinimal ? 120 : 500
        p.minSize = isMinimal ? NSSize(width: 240, height: 100) : NSSize(width: 240, height: 240)
        let newFrame = NSRect(x: p.frame.minX, y: p.frame.maxY - targetH,
                              width: p.frame.width, height: targetH)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            p.animator().setFrame(newFrame, display: true)
        }
    }
}
