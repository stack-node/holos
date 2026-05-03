import SwiftUI
import AppKit

// MARK: - Drag state

@MainActor
final class WidgetDragState: ObservableObject {
    static let shared = WidgetDragState()
    private init() {}

    @Published private(set) var isDragging = false
    @Published private(set) var draggingWidgetID: String? = nil

    func startDrag(id: String, fromZone: String? = nil) {
        guard !isDragging else { return }
        isDragging = true
        draggingWidgetID = id
        WidgetZoneManager.shared.showZones(excludingZone: fromZone)
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        draggingWidgetID = nil
        WidgetZoneManager.shared.hideZones()
    }
}

// MARK: - Zone highlight state

@MainActor
final class ZoneHighlightState: ObservableObject {
    @Published var isHighlighted = false
}

// MARK: - Zone drop target view

struct WidgetZoneDropView: View {
    @ObservedObject var highlight: ZoneHighlightState
    @State private var pulse = false

    private let cyan = Color(red: 0.2, green: 0.85, blue: 1.0)

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(cyan.opacity(highlight.isHighlighted ? 0.14 : (pulse ? 0.07 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        cyan.opacity(highlight.isHighlighted ? 1.0 : (pulse ? 0.65 : 0.35)),
                        style: StrokeStyle(
                            lineWidth: highlight.isHighlighted ? 2 : 1.5,
                            dash: [6, 4]
                        )
                    )
            )
            .animation(.easeInOut(duration: 0.1), value: highlight.isHighlighted)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Zone manager

@MainActor
final class WidgetZoneManager: ObservableObject {
    static let shared = WidgetZoneManager()
    private init() { load() }

    // zoneID → extensionID, persisted
    @Published private(set) var assignments: [String: String] = [:]

    private var dragEntries: [(id: String, frame: NSRect, panel: NSPanel, highlight: ZoneHighlightState)] = []

    static let zoneGap: CGFloat    = 5
    static let zoneHeight: CGFloat = 72

    // MARK: Persistence

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holos/configuration/widget-zones.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: configURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        assignments = dict
    }

    func save() {
        try? JSONEncoder().encode(assignments).write(to: configURL)
    }

    // MARK: Drag phase

    func showZones(excludingZone: String? = nil) {
        clearDragPanels()
        let pm = PinManager.shared

        if pm.isSidebarOpen, let sf = pm.stableSidebarFrame {
            let id = "below-left-sidebar"
            guard id != excludingZone else { return }
            let frame = NSRect(
                x: sf.minX,
                y: sf.minY - Self.zoneGap - Self.zoneHeight,
                width: sf.width,
                height: Self.zoneHeight
            )
            let hl    = ZoneHighlightState()
            let panel = makeDragPanel(frame: frame, highlight: hl)
            dragEntries.append((id: id, frame: frame, panel: panel, highlight: hl))
        }
    }

    func hideZones() {
        clearDragPanels()
    }

    func updateHighlight(at point: NSPoint) {
        for entry in dragEntries {
            entry.highlight.isHighlighted = entry.frame.contains(point)
        }
    }

    @discardableResult
    func commit(extensionID: String, at point: NSPoint, sourceZone: String? = nil) -> Bool {
        guard let entry = dragEntries.first(where: { $0.frame.contains(point) }) else { return false }
        if let src = sourceZone, src != entry.id { assignments.removeValue(forKey: src) }
        assignments[entry.id] = extensionID
        save()
        PinManager.shared.refreshWidgetPanels()
        return true
    }

    func removeAssignment(for zoneID: String) {
        assignments.removeValue(forKey: zoneID)
        save()
        PinManager.shared.refreshWidgetPanels()
    }

    // MARK: Widget panel frame (for PinManager)

    func widgetPanelFrame(for zoneID: String) -> NSRect? {
        switch zoneID {
        case "below-left-sidebar":
            guard let sf = PinManager.shared.stableSidebarFrame else { return nil }
            return NSRect(
                x: sf.minX,
                y: sf.minY - Self.zoneGap - Self.zoneHeight,
                width: sf.width,
                height: Self.zoneHeight
            )
        default: return nil
        }
    }

    // MARK: Helpers

    private func clearDragPanels() {
        dragEntries.forEach { entry in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                entry.panel.animator().alphaValue = 0
            }, completionHandler: { entry.panel.orderOut(nil) })
        }
        dragEntries.removeAll()
    }

    private func makeDragPanel(frame: NSRect, highlight: ZoneHighlightState) -> NSPanel {
        let p = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: WidgetZoneDropView(highlight: highlight))
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }
        return p
    }
}
