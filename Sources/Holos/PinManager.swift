import AppKit
import SwiftUI
import Combine

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PinManager: ObservableObject {
    static let shared = PinManager()
    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.leftSidebarWidthKey)
        if stored >= leftSidebarMinW && stored <= leftSidebarMaxW {
            sidebarW = stored
        }
    }

    @Published private(set) var isShowing = false
    @Published var isSticky = false
    @Published var isPinned = PinManager.loadIsPinnedFromDefaults() {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: Self.isPinnedKey)
            applyPinState()
        }
    }
    @Published private(set) var isSidebarOpen = false
    @Published private(set) var isRightSidebarOpen = false

    private var panel: NSPanel?
    private var sidebarPanel: NSPanel?
    private var rightSidebarPanel: NSPanel?
    private var blurView: NSVisualEffectView?
    private var mainResizeOverlay: MainWindowResizeChromeView?
    private var sidebarBlurView: NSVisualEffectView?
    private var rightSidebarBlurView: NSVisualEffectView?
    var mainPanelFrame: NSRect?    { panel?.frame }
    var sidebarPanelFrame: NSRect? { sidebarPanel?.frame }
    var stableSidebarFrame: NSRect? {
        guard let main = panel else { return nil }
        return sidebarFrame(for: main.frame)
    }

    private var widgetPanels: [String: NSPanel] = [:]

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
        // Reuse existing panel — preserves all SwiftUI @State (tabs, sidebar state, etc.)
        if let p = panel {
            p.makeKeyAndOrderFront(nil)
            if isSidebarOpen      { sidebarPanel?.makeKeyAndOrderFront(nil) }
            if isRightSidebarOpen { rightSidebarPanel?.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
            isShowing = true
            refreshWidgetPanels()
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
        p.minSize = NSSize(width: 240, height: 1)

        let config = HolosConfig.shared
        let blur = MovableVisualEffectView()
        blur.material = config.blurMaterial
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blurView = blur

        let hosting = MenuBarHostingView(rootView: MenuBarView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
        ])

        let resizeEdge = MainWindowResizeChromeView()
        resizeEdge.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(resizeEdge)
        NSLayoutConstraint.activate([
            resizeEdge.topAnchor.constraint(equalTo: blur.topAnchor),
            resizeEdge.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            resizeEdge.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            resizeEdge.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
        ])
        mainResizeOverlay = resizeEdge

        p.contentView = blur

        config.$blurStrength
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.blurView?.material = HolosConfig.shared.blurMaterial
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
        refreshWidgetPanels()
        applyPinState()
    }

    func hide() {
        // Just hide panels — don't tear down, preserves state for next show
        if let main = panel {
            for w in widgetPanels.values {
                if w.parent === main { main.removeChildWindow(w) }
                w.orderOut(nil)
            }
        } else {
            widgetPanels.values.forEach { $0.orderOut(nil) }
        }
        sidebarPanel?.orderOut(nil)
        rightSidebarPanel?.orderOut(nil)
        panel?.orderOut(nil)
        isShowing = false
    }

    // MARK: - Sidebar

    private static let isPinnedKey = "holos.windowPinned"
    private static let leftSidebarWidthKey = "holos.leftSidebarWidth"

    private static func loadIsPinnedFromDefaults() -> Bool {
        guard UserDefaults.standard.object(forKey: isPinnedKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: isPinnedKey)
    }
    private let leftSidebarMinW: CGFloat = 160
    private let leftSidebarMaxW: CGFloat = 480

    @Published private(set) var sidebarW: CGFloat = 200
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

    func resizeLeftSidebar(to width: CGFloat) {
        guard let main = panel, let sp = sidebarPanel else { return }
        sidebarW = min(leftSidebarMaxW, max(leftSidebarMinW, width))
        UserDefaults.standard.set(sidebarW, forKey: Self.leftSidebarWidthKey)
        sp.setFrame(sidebarFrame(for: main.frame), display: true)
        reframeWidgetPanels()
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

            let config = HolosConfig.shared
            let blur = MovableVisualEffectView()
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
                .sink { [weak self] _ in self?.sidebarBlurView?.material = HolosConfig.shared.blurMaterial }
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

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            sp.animator().setFrame(target, display: true)
            sp.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.refreshWidgetPanels()
        })

        let reframeSidebar = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let main = self.panel, let sp = self.sidebarPanel else { return }
                sp.setFrame(self.sidebarFrame(for: main.frame), display: true)
                self.reframeWidgetPanels()
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

        hideAllWidgetPanels()

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

            let config = HolosConfig.shared
            let blur = MovableVisualEffectView()
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
                .sink { [weak self] _ in self?.rightSidebarBlurView?.material = HolosConfig.shared.blurMaterial }
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
        let start  = NSRect(x: main.frame.maxX - rightSidebarW, y: target.minY,
                            width: rightSidebarW, height: target.height)

        sp.setFrame(start, display: false)
        sp.alphaValue = 0
        // Below main so the editor reads as stacked under the main window. Right-pane
        // context switching uses a popover (menu-style pickers do not present reliably on this panel).
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

        let endFrame = NSRect(x: main.frame.maxX - rightSidebarW, y: sp.frame.minY,
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

    // MARK: - Widget panels

    /// Widget-zone UI depends on a live extension process; skip creating panels until it is running.
    private static func extensionIsRunningForWidget(extensionID: String) -> Bool {
        guard let ext = ExtensionManager.shared.extensions.first(where: { $0.id == extensionID }) else {
            return false
        }
        let isWidgetExtension = ext.manifest.provides.contains("widget") || ext.widgetSpec != nil
        if !isWidgetExtension { return true }
        if case .running = ext.runState { return true }
        return false
    }

    func refreshWidgetPanels() {
        let mgr = WidgetZoneManager.shared
        for (zoneID, extIDs) in mgr.assignments {
            let shouldShow: Bool
            switch zoneID {
            case "below-left-sidebar": shouldShow = isSidebarOpen && isShowing
            default:                   shouldShow = isShowing
            }
            let anyReady = extIDs.contains { Self.extensionIsRunningForWidget(extensionID: $0) }
            if shouldShow && anyReady { showWidgetPanel(zoneID: zoneID) }
            else                       { hideWidgetPanel(zoneID: zoneID) }
        }
        for zoneID in widgetPanels.keys where mgr.assignments[zoneID] == nil {
            hideWidgetPanel(zoneID: zoneID)
        }
    }

    /// Child of main so widget panels track drags in sync (same idea as sidebar child windows).
    private func attachWidgetPanelToMain(_ w: NSWindow) {
        guard let main = panel else { return }
        if w.parent === main { return }
        if let old = w.parent { old.removeChildWindow(w) }
        main.addChildWindow(w, ordered: .below)
    }

    private func showWidgetPanel(zoneID: String) {
        guard let frame = WidgetZoneManager.shared.widgetPanelFrame(for: zoneID) else { return }
        if let existing = widgetPanels[zoneID] {
            existing.setFrame(frame, display: true)
            attachWidgetPanelToMain(existing)
            return
        }

        let config = HolosConfig.shared
        let blur = MovableVisualEffectView()
        blur.material = config.blurMaterial
        blur.blendingMode = config.blurEnabled ? .behindWindow : .withinWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView:
            WidgetPanelContentView(zoneID: zoneID)
                .preferredColorScheme(.dark)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
        ])

        let p = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.contentView = blur

        p.alphaValue = 0
        attachWidgetPanelToMain(p)
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }
        widgetPanels[zoneID] = p
    }

    private func hideWidgetPanel(zoneID: String) {
        guard let p = widgetPanels.removeValue(forKey: zoneID) else { return }
        if let main = panel, p.parent === main {
            main.removeChildWindow(p)
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    private func hideAllWidgetPanels() {
        widgetPanels.keys.forEach { hideWidgetPanel(zoneID: $0) }
    }

    private func reframeWidgetPanels() {
        for (zoneID, p) in widgetPanels {
            if let frame = WidgetZoneManager.shared.widgetPanelFrame(for: zoneID) {
                p.setFrame(frame, display: true)
            }
        }
    }

    private func applyPinState() {
        guard let p = panel else { return }
        if isPinned {
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            sidebarPanel?.level = .floating
            sidebarPanel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            rightSidebarPanel?.level = .floating
            rightSidebarPanel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            p.level = .normal
            p.collectionBehavior = []
            widgetPanels.values.forEach { $0.level = .normal; $0.collectionBehavior = [] }
            sidebarPanel?.level = .normal
            sidebarPanel?.collectionBehavior = []
            rightSidebarPanel?.level = .normal
            rightSidebarPanel?.collectionBehavior = []
        }
    }
}
