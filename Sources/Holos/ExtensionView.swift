import SwiftUI
import AppKit

// MARK: - Window drag exclusion

private final class _NonDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

private struct WindowDragExclusion: NSViewRepresentable {
    func makeNSView(context: Context) -> _NonDraggableView { _NonDraggableView() }
    func updateNSView(_ nsView: _NonDraggableView, context: Context) {}
}

// MARK: - Extensions page

struct ExtensionListView: View {
    @ObservedObject private var manager = ExtensionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 52)

            HStack {
                Text("Extensions")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button { manager.scan() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if manager.extensions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(manager.extensions) { ext in
                            ExtensionRow(ext: ext)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.35))
            Text("No extensions")
                .font(.system(.callout))
                .foregroundStyle(.white.opacity(0.3))
            Text("~/.config/holos/extensions/")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.18))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Extension row

struct ExtensionRow: View {
    @ObservedObject var ext: HolosExtension
    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: stateColor.opacity(0.8), radius: 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ext.manifest.name)
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(ext.manifest.description)
                        .font(.system(.caption2))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                if ext.manifest.provides.contains("widget") {
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: 10))
                        .foregroundStyle(isDragging
                            ? Color(red: 0.2, green: 0.85, blue: 1.0).opacity(0.9)
                            : .white.opacity(0.18))
                }
            }

            HStack(spacing: 5) {
                ctrlBtn("play.fill",         "Start",   enabled: ext.canStart)             { ext.start() }
                ctrlBtn("stop.fill",          "Stop",    enabled: ext.runState == .running)  { ext.stop() }
                ctrlBtn("arrow.clockwise",    "Restart", enabled: ext.runState == .running)  { ext.restart() }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(isDragging ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(
                            isDragging
                                ? Color(red: 0.2, green: 0.85, blue: 1.0).opacity(0.45)
                                : Color.white.opacity(0.07),
                            lineWidth: 0.8
                        )
                )
        )
        .scaleEffect(isDragging ? 0.97 : 1)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .background(WindowDragExclusion())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in
                    guard NSEvent.modifierFlags.contains(.command) else { return }
                    if !isDragging {
                        isDragging = true
                        WidgetDragState.shared.startDrag(id: ext.id)
                    }
                    WidgetZoneManager.shared.updateHighlight(at: NSEvent.mouseLocation)
                }
                .onEnded { _ in
                    if isDragging {
                        WidgetZoneManager.shared.commit(extensionID: ext.id, at: NSEvent.mouseLocation)
                    }
                    isDragging = false
                    WidgetDragState.shared.endDrag()
                }
        )
    }

    private var stateColor: Color {
        switch ext.runState {
        case .stopped:  return .white.opacity(0.2)
        case .starting: return .yellow
        case .running:  return Color(red: 0.15, green: 1, blue: 0.45)
        case .failed:   return .red
        }
    }

    private func ctrlBtn(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 8, weight: .semibold))
                Text(label).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(enabled ? .white.opacity(0.7) : .white.opacity(0.2))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(enabled ? Color.white.opacity(0.08) : Color.white.opacity(0.03)))
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }
}

// MARK: - Extension widget view (placed in zones)

struct ExtensionWidgetView: View {
    @ObservedObject var ext: HolosExtension

    var body: some View {
        switch ext.manifest.id {
        case "music": MusicExtensionWidget(ext: ext)
        default:      GenericExtensionWidget(ext: ext)
        }
    }
}

// Music renderer
private struct MusicExtensionWidget: View {
    @ObservedObject var ext: HolosExtension

    private var state:     String { ext.widgetData["state"]  ?? "stopped" }
    private var track:     String { ext.widgetData["track"]  ?? "" }
    private var artist:    String { ext.widgetData["artist"] ?? "" }
    private var isPlaying: Bool   { state == "playing" }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.55).opacity(0.75))
                Text("MUSIC")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            }
            .padding(.horizontal, 10)

            if track.isEmpty {
                Text("Nothing playing")
                    .font(.system(.caption2))
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.horizontal, 10)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)

                HStack(spacing: 0) {
                    mediaBtn("backward.end.fill") { ext.sendCommand("previous") }
                    mediaBtn(isPlaying ? "pause.fill" : "play.fill") { ext.sendCommand("play_pause") }
                    mediaBtn("forward.end.fill")  { ext.sendCommand("next") }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
        )
        .padding(.horizontal, 8)
    }

    private func mediaBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

// Generic fallback renderer
private struct GenericExtensionWidget: View {
    @ObservedObject var ext: HolosExtension

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ext.manifest.name.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 10)
            ForEach(ext.widgetData.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text(ext.widgetData[key] ?? "").foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
        )
        .padding(.horizontal, 8)
    }
}

// MARK: - Widget panel content (rendered inside placed zone panel)

struct WidgetPanelContentView: View {
    let extensionID: String
    let zoneID: String
    @ObservedObject private var manager = ExtensionManager.shared
    @State private var isDragging = false

    var body: some View {
        if let ext = manager.extensions.first(where: { $0.id == extensionID }) {
            ExtensionWidgetView(ext: ext)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isDragging ? 0.4 : 1)
                .scaleEffect(isDragging ? 0.96 : 1)
                .animation(.easeInOut(duration: 0.15), value: isDragging)
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in
                            guard NSEvent.modifierFlags.contains(.command) else { return }
                            if !isDragging {
                                isDragging = true
                                WidgetDragState.shared.startDrag(id: extensionID, fromZone: zoneID)
                            }
                            WidgetZoneManager.shared.updateHighlight(at: NSEvent.mouseLocation)
                        }
                        .onEnded { _ in
                            if isDragging {
                                let placed = WidgetZoneManager.shared.commit(
                                    extensionID: extensionID,
                                    at: NSEvent.mouseLocation,
                                    sourceZone: zoneID
                                )
                                if !placed { WidgetZoneManager.shared.removeAssignment(for: zoneID) }
                            }
                            isDragging = false
                            WidgetDragState.shared.endDrag()
                        }
                )
        }
    }
}
