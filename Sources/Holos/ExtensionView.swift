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
    @State private var selectedTab = "Installed"

    private let tabs = ["Installed", "Browse"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 52)

            ZStack {
                PillTabStrip(tabs: tabs, selection: $selectedTab)
                HStack {
                    Spacer(minLength: 0)
                    if selectedTab == "Installed" {
                        Button { manager.scan() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal, 46)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Group {
                if selectedTab == "Installed" {
                    installedContent
                } else {
                    browsePlaceholder
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var installedContent: some View {
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

    private var browsePlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color(red: 0.40, green: 0.85, blue: 0.85).opacity(0.5))
            Text("Browse")
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("Coming soon")
                .font(.system(.caption))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.top, 52)
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

    private var isWidgetExtension: Bool {
        ext.manifest.provides.contains("widget") || ext.widgetSpec != nil
    }

    private var widgetExtensionMayShowContent: Bool {
        guard isWidgetExtension else { return true }
        if case .running = ext.runState { return true }
        return false
    }

    var body: some View {
        if !widgetExtensionMayShowContent {
            EmptyView()
        } else if let spec = ext.widgetSpec {
            DeclarativeExtensionWidget(ext: ext, spec: spec)
        } else if ext.manifest.provides.contains("widget") {
            GenericExtensionWidget(ext: ext)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Declarative JSON widget

private struct DeclarativeExtensionWidget: View {
    @ObservedObject var ext: HolosExtension
    let spec: ExtensionWidgetSpec

    var body: some View {
        Group {
            if spec.version == 1 {
                WidgetNodeView(ext: ext, node: spec.root)
            } else {
                Text("Unsupported widget schema version \(spec.version)")
                    .font(.system(.caption2))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 8)
    }
}

/// Renders one `WidgetNode` and recurses through children (concrete `View` type avoids opaque recursion issues).
private struct WidgetNodeView: View {
    @ObservedObject var ext: HolosExtension
    let node: WidgetNode

    var body: some View {
        switch node {
        case .vstack(let s):
            let align = Self.horizontalAlignment(s.horizontalAlignment)
            VStack(alignment: align, spacing: CGFloat(s.spacing ?? 0)) {
                ForEach(s.children.indices, id: \.self) { i in
                    WidgetNodeView(ext: ext, node: s.children[i])
                }
            }
            .modifier(HorizontalPad(value: s.horizontalPadding))

        case .hstack(let s):
            let align = Self.verticalAlignment(s.verticalAlignment)
            HStack(alignment: align, spacing: CGFloat(s.spacing ?? 0)) {
                ForEach(s.children.indices, id: \.self) { i in
                    WidgetNodeView(ext: ext, node: s.children[i])
                }
            }
            .modifier(HorizontalPad(value: s.horizontalPadding))

        case .text(let t):
            textView(t)

        case .symbol(let s):
            Image(systemName: s.systemName)
                .font(Self.symbolFont(s))
                .foregroundStyle(Self.symbolForeground(s))
                .modifier(HorizontalPad(value: s.horizontalPadding))

        case .button(let b):
            Button {
                ext.sendCommand(b.command)
            } label: {
                let iconName = Self.resolvedIcon(b, data: ext.widgetData)
                Group {
                    if b.fillWidth == true {
                        Image(systemName: iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, minHeight: 22)
                            .contentShape(Rectangle())
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(minHeight: 22)
                            .contentShape(Rectangle())
                    }
                }
            }
            .buttonStyle(.borderless)
            .modifier(HorizontalPad(value: b.horizontalPadding))

        case .spacer(let s):
            Spacer(minLength: CGFloat(s.minLength ?? 0))

        case .whenEmpty(let w):
            let empty = (ext.widgetData[w.binding] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Group {
                if empty {
                    ForEach(w.whenEmpty.indices, id: \.self) { i in
                        WidgetNodeView(ext: ext, node: w.whenEmpty[i])
                    }
                } else {
                    ForEach(w.elseNodes.indices, id: \.self) { i in
                        WidgetNodeView(ext: ext, node: w.elseNodes[i])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func textView(_ t: WidgetText) -> some View {
        let base = Text(resolvedText(t))
            .font(Self.textFont(t))
            .foregroundStyle(Self.foregroundStyle(opacity: t.foregroundOpacity ?? 0.85))
        if let lim = t.lineLimit, lim > 0 {
            base.lineLimit(lim).modifier(HorizontalPad(value: t.horizontalPadding))
        } else {
            base.modifier(HorizontalPad(value: t.horizontalPadding))
        }
    }

    private func resolvedText(_ t: WidgetText) -> String {
        if let b = t.binding {
            return ext.widgetData[b] ?? ""
        }
        return t.text ?? ""
    }

    private static func textFont(_ t: WidgetText) -> Font {
        if let name = t.textStyle?.lowercased() {
            switch name {
            case "caption2": return .system(.caption2)
            case "caption":  return .system(.caption)
            case "callout":  return .system(.callout)
            case "body":     return .system(.body)
            default:         break
            }
        }
        let size = CGFloat(t.fontSize ?? 11)
        let w = fontWeight(t.fontWeight)
        switch t.design?.lowercased() {
        case "monospaced":
            return .system(size: size, weight: w, design: .monospaced)
        default:
            return .system(size: size, weight: w)
        }
    }

    private static func fontWeight(_ raw: String?) -> Font.Weight {
        switch raw?.lowercased() {
        case "semibold": return .semibold
        case "medium":   return .medium
        case "bold":     return .bold
        case "light":    return .light
        default:         return .regular
        }
    }

    private static func symbolFont(_ s: WidgetSymbol) -> Font {
        let size = CGFloat(s.fontSize ?? 11)
        return .system(size: size, weight: fontWeight(s.fontWeight))
    }

    private static func symbolForeground(_ s: WidgetSymbol) -> Color {
        let o = CGFloat(s.foregroundOpacity ?? 1)
        if let rgb = s.foregroundRGB, rgb.count == 3 {
            return Color(red: rgb[0], green: rgb[1], blue: rgb[2]).opacity(o)
        }
        return Color.white.opacity(o)
    }

    private static func foregroundStyle(opacity: Double) -> Color {
        .white.opacity(CGFloat(opacity))
    }

    private static func resolvedIcon(_ b: WidgetButton, data: [String: String]) -> String {
        if let when = b.iconWhen,
           (data[when.binding] ?? "") == when.equals {
            return when.icon
        }
        return b.icon
    }

    private static func horizontalAlignment(_ raw: String?) -> HorizontalAlignment {
        switch raw?.lowercased() {
        case "center":   return .center
        case "trailing": return .trailing
        default:         return .leading
        }
    }

    private static func verticalAlignment(_ raw: String?) -> VerticalAlignment {
        switch raw?.lowercased() {
        case "top":      return .top
        case "bottom":   return .bottom
        default:         return .center
        }
    }
}

private struct HorizontalPad: ViewModifier {
    let value: Double?
    func body(content: Content) -> some View {
        if let v = value {
            content.padding(.horizontal, CGFloat(v))
        } else {
            content
        }
    }
}

// Generic fallback renderer (no `widget` in manifest / widget.json)
private struct GenericExtensionWidget: View {
    @ObservedObject var ext: HolosExtension

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            Text("Add a \"widget\" object to manifest.json or ship widget.json for a custom layout.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.horizontal, 10)
                .padding(.top, 2)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
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
                                _ = WidgetZoneManager.shared.commit(
                                    extensionID: extensionID,
                                    at: NSEvent.mouseLocation,
                                    sourceZone: zoneID
                                )
                            }
                            isDragging = false
                            WidgetDragState.shared.endDrag()
                        }
                )
        }
    }
}
