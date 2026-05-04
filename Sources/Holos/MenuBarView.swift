import SwiftUI
import AppKit

// MARK: - Main view

struct MenuBarView: View {
    @ObservedObject private var server     = LlamaServer.shared
    @ObservedObject private var chat       = ChatClient.shared
    @ObservedObject private var config     = HolosConfig.shared
    @ObservedObject private var pinManager = PinManager.shared
    @State private var inputText = ""
    @State private var edgePhase: CGFloat = 0
    @State private var isHoveringLeft   = false
    @State private var showingLog       = false
    @State private var showingAppearance = false
    @ObservedObject private var rightState = RightSidebarState.shared
    var body: some View {
        mainPanel
        .frame(minWidth: 240, idealWidth: 380, idealHeight: 500)
        .ignoresSafeArea(.all, edges: .top)
        .background(
            ZStack {
                if config.blurEnabled {
                    Color.black.opacity(config.backgroundOpacity)
                } else {
                    Color(white: 0.08).opacity(0.95)
                }
                liquidGlassEdge
            }
            .ignoresSafeArea()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.55, green: 0.25, blue: 0.95).opacity(0.7), location: 0),
                            .init(color: Color(red: 0.9,  green: 0.3,  blue: 0.6 ).opacity(0.5), location: 0.25),
                            .init(color: Color(red: 0.5,  green: 0.3,  blue: 0.75).opacity(0.15), location: 0.5),
                            .init(color: Color(red: 0.1,  green: 0.7,  blue: 0.7 ).opacity(0.5), location: 0.75),
                            .init(color: Color(red: 0.2,  green: 0.85, blue: 1.0 ).opacity(0.6), location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 0.8
                )
        )
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                edgePhase = 1
            }
        }
    }

    // MARK: Main panel

    @ObservedObject private var nav = NavigationState.shared

    private var mainPanel: some View {
        ZStack {
            // Content
            VStack(spacing: 0) {
                if let g = nav.globalTab {
                    globalPlaceholderPage(for: g)
                } else if nav.selectedTab == "Chats" {
                    messagesArea
                    inputSection
                } else {
                    placeholderPage(for: nav.selectedTab)
                }
            }

            // Left strip: all hover-only controls
            ZStack(alignment: .top) {
                Color.clear
                if isHoveringLeft || showingLog || showingAppearance {
                    VStack(spacing: 16) {
                        iconButton(pinManager.isPinned ? "pin.fill" : "pin",
                                   active: pinManager.isPinned) {
                            pinManager.isPinned.toggle()
                        }
                        iconButton("trash", active: false) { chat.clearHistory() }
                        iconButton("terminal", active: showingLog) {
                            showingLog.toggle(); showingAppearance = false
                        }
                        .popover(isPresented: $showingLog, arrowEdge: .leading) {
                            LogView()
                                .frame(width: 360, height: 300)
                                .preferredColorScheme(.dark)
                        }
                        iconButton("paintbrush", active: showingAppearance) {
                            showingAppearance.toggle(); showingLog = false
                        }
                        .popover(isPresented: $showingAppearance, arrowEdge: .leading) {
                            AppearanceView()
                                .frame(width: 280)
                                .preferredColorScheme(.dark)
                        }
                    }
                    .padding(.top, 52)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
            .frame(width: 36)
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHoveringLeft = hovering }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // AppKit-backed strip: reliable window drag (placed under sidebar buttons; center passes through Spacer).
            WindowTitleBarDragArea()
                .frame(height: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

// Sidebar toggles — topmost layer, receive taps
            HStack(alignment: .top) {
                Button { pinManager.toggleSidebar() } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(pinManager.isSidebarOpen ? .white.opacity(0.8) : .white.opacity(0.45))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(pinManager.isSidebarOpen ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.borderless)
                .padding(.leading, 10)

                Spacer().allowsHitTesting(false)

                Button { pinManager.toggleRightSidebar() } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(pinManager.isRightSidebarOpen ? .white.opacity(0.8) : .white.opacity(0.45))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(pinManager.isRightSidebarOpen ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 10)
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder private var liquidGlassEdge: some View {
        if config.glowStyle != .off {
            let glow      = CGFloat(config.glowSize)
            let blur      = CGFloat(config.glowBlur)
            let intensity = config.glowIntensity
            Canvas { ctx, size in
                if config.glowStyle == .mimicBorder {
                    let edgeH = glow * 2.5
                    let edgeW = glow * 2.5
                    let op = (0.28 + edgePhase * 0.10) * intensity
                    let hGrad = Gradient(stops: [
                        .init(color: Color(red: 0.55, green: 0.25, blue: 0.95).opacity(op), location: 0.00),
                        .init(color: Color(red: 0.9,  green: 0.3,  blue: 0.6 ).opacity(op), location: 0.25),
                        .init(color: Color(red: 0.5,  green: 0.2,  blue: 0.1 ).opacity(op * 0.25), location: 0.50),
                        .init(color: Color(red: 0.1,  green: 0.7,  blue: 0.7 ).opacity(op), location: 0.75),
                        .init(color: Color(red: 0.2,  green: 0.85, blue: 1.0 ).opacity(op), location: 1.00),
                    ])
                    // Top edge — full-width gradient strip
                    ctx.drawLayer { c in
                        c.addFilter(.blur(radius: blur * 1.4))
                        c.fill(Path(CGRect(x: 0, y: -edgeH * 0.5, width: size.width, height: edgeH)),
                               with: .linearGradient(hGrad,
                                   startPoint: CGPoint(x: 0, y: 0),
                                   endPoint: CGPoint(x: size.width, y: 0),
                                   options: []))
                    }
                    // Bottom edge — full-width gradient strip
                    ctx.drawLayer { c in
                        c.addFilter(.blur(radius: blur * 1.4))
                        c.fill(Path(CGRect(x: 0, y: size.height - edgeH * 0.5, width: size.width, height: edgeH)),
                               with: .linearGradient(hGrad,
                                   startPoint: CGPoint(x: 0, y: 0),
                                   endPoint: CGPoint(x: size.width, y: 0),
                                   options: []))
                    }
                    // Left edge — purple, full height
                    ctx.drawLayer { c in
                        c.addFilter(.blur(radius: blur * 1.4))
                        c.fill(Path(CGRect(x: -edgeW * 0.5, y: 0, width: edgeW, height: size.height)),
                               with: .color(Color(red: 0.55, green: 0.25, blue: 0.95).opacity(op)))
                    }
                    // Right edge — cyan, full height
                    ctx.drawLayer { c in
                        c.addFilter(.blur(radius: blur * 1.4))
                        c.fill(Path(CGRect(x: size.width - edgeW * 0.5, y: 0, width: edgeW, height: size.height)),
                               with: .color(Color(red: 0.2, green: 0.85, blue: 1.0).opacity(op)))
                    }
                } else {
                    let colors = glowColors
                    let r: CGFloat = 12
                    let half = glow * 0.5
                    let inner = CGRect(x: half, y: half,
                                       width: size.width - glow,
                                       height: size.height - glow)
                    let path = Path(roundedRect: inner, cornerRadius: max(1, r - half))
                    ctx.drawLayer { c in
                        c.addFilter(.blur(radius: blur * 0.85))
                        c.stroke(path, with: .color(colors.0.opacity((0.18 + edgePhase * 0.07) * intensity)), lineWidth: glow)
                    }
                    ctx.drawLayer { c in
                        c.addFilter(.blur(radius: blur * 1.15))
                        c.stroke(path, with: .color(colors.1.opacity((0.12 + edgePhase * 0.05) * intensity)), lineWidth: glow)
                    }
                    ctx.drawLayer { c in
                        c.addFilter(.blur(radius: blur))
                        c.stroke(path, with: .color(colors.2.opacity((0.14 + (1 - edgePhase) * 0.06) * intensity)), lineWidth: glow)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var glowColors: (Color, Color, Color) {
        switch config.glowStyle {
        case .off:
            return (.clear, .clear, .clear)
        case .solidColor:
            let h = dominantHue
            return (
                Color(red: config.glowColorR, green: config.glowColorG, blue: config.glowColorB),
                Color(hue: fmod(h + 0.33, 1), saturation: 0.7, brightness: 0.9),
                Color(hue: fmod(h + 0.66, 1), saturation: 0.65, brightness: 0.95)
            )
        case .mimicBorder:
            return (.clear, .clear, .clear) // handled separately
        }
    }

    private var dominantHue: Double {
        let r = config.glowColorR, g = config.glowColorG, b = config.glowColorB
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0 else { return 0 }
        let h: Double
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        return h / 6
    }

    private var hairline: some View {
        Color.white.opacity(0.07).frame(height: 0.5)
    }

    // MARK: Placeholder pages

    private func placeholderTabTitle(for tab: String) -> String {
        switch tab {
        case "soundMap":   return "Map"
        case "soundMixer": return "Mixer"
        default:           return tab
        }
    }

    private func placeholderPage(for tab: String) -> some View {
        if tab == "Settings" {
            return AnyView(SettingsView().frame(maxWidth: .infinity, maxHeight: .infinity))
        }
        let meta: (icon: String, color: Color) = {
            switch tab {
            case "Models":      return ("cube",                                        Color(red: 0.55, green: 0.40, blue: 0.90))
            case "Tools":       return ("wrench.and.screwdriver",                      Color(red: 1.00, green: 0.65, blue: 0.30))
            case "Knowledge":   return ("cylinder.split.1x2",                          Color(red: 0.90, green: 0.40, blue: 0.50))
            case "Connections": return ("point.3.connected.trianglepath.dotted",       Color(red: 0.40, green: 0.85, blue: 0.85))
            case "Skills":      return ("sparkles",                                    Color(red: 0.95, green: 0.80, blue: 0.35))
            case "Rules":       return ("list.bullet.rectangle",                       Color(red: 0.55, green: 0.85, blue: 0.55))
            case "Map":         return ("point.3.filled.connected.trianglepath.dotted",Color(red: 0.65, green: 0.50, blue: 0.95))
            case "soundMap":    return ("point.3.filled.connected.trianglepath.dotted",Color(red: 0.65, green: 0.50, blue: 0.95))
            case "soundMixer":  return ("slider.horizontal.3",                         Color(red: 0.95, green: 0.42, blue: 0.52))
            default:            return ("square.dashed",                               Color.white)
            }
        }()
        let title = placeholderTabTitle(for: tab)
        return AnyView(
            VStack(spacing: 14) {
                Image(systemName: meta.icon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(meta.color.opacity(0.5))
                Text(title)
                    .font(.system(.title3, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Coming soon")
                    .font(.system(.caption))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.top, 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }

    private func globalPlaceholderPage(for tab: String) -> some View {
        if tab == "Extensions" {
            return AnyView(ExtensionListView().frame(maxWidth: .infinity, maxHeight: .infinity))
        }
        let meta: (icon: String, color: Color) = {
            switch tab {
            case "Modules":  return ("square.stack.3d.up.fill", Color(red: 0.45, green: 0.82, blue: 0.92))
            case "Settings": return ("gearshape.2", Color(red: 0.70, green: 0.70, blue: 0.75))
            default:         return ("square.dashed", Color.white)
            }
        }()
        return AnyView(
            VStack(spacing: 14) {
                Image(systemName: meta.icon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(meta.color.opacity(0.5))
                Text(tab)
                    .font(.system(.title3, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Coming soon")
                    .font(.system(.caption))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.top, 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }

    // MARK: Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chat.messages) { msg in
                        GlassMessageBubble(message: msg)
                    }
                    if chat.isStreaming && !chat.streamingResponse.isEmpty {
                        GlassMessageBubble(
                            message: ChatMessage(role: "assistant", content: chat.streamingResponse)
                        ).id("streaming")
                    }
                    if let err = chat.error {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.75))
                            .padding(.horizontal, 16)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: chat.messages.count) { _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: chat.streamingResponse) { _ in
                proxy.scrollTo("bottom")
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Input section

    private var inputSection: some View {
        VStack(spacing: 6) {
            if let suggestion = chat.refinedPrompt, !suggestion.isEmpty {
                refinementBanner(suggestion)
            }
            LiquidGlassInput(
                text: $inputText,
                placeholder: "Message Holos",
                isRefining: chat.isRefining,
                isStreaming: chat.isStreaming,
                canSend: !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && server.isRunning,
                onSend: sendMessage,
                onRefine: { chat.refine(inputText) },
                onStop: { chat.cancel() }
            )
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 8)
    }

    private func refinementBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.caption2)
                .foregroundStyle(Color.purple.opacity(0.8))
                .padding(.top, 2)
            Text(text)
                .font(.system(.caption))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    inputText = text
                    chat.dismissRefinement()
                }
            if chat.isRefining {
                ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
            }
            Button(action: { chat.dismissRefinement() }) {
                Image(systemName: "xmark").font(.caption2).foregroundStyle(.white.opacity(0.3))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.18), lineWidth: 0.5))
        )
        .padding(.horizontal, 12)
    }



    private func iconButton(_ name: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(active ? .white.opacity(0.85) : .white.opacity(0.3))
    }

    // MARK: Helpers

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, server.isRunning else { return }
        inputText = ""
        chat.send(trimmed)
    }
}

// MARK: - Liquid glass input

struct LiquidGlassInput: View {
    @Binding var text: String
    let placeholder: String
    let isRefining: Bool
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onRefine: () -> Void
    let onStop: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12, opacity: 0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.55, green: 0.25, blue: 0.95).opacity(0.7), location: 0),
                                .init(color: Color(red: 0.9,  green: 0.3,  blue: 0.6 ).opacity(0.5), location: 0.25),
                                .init(color: Color(red: 0.5,  green: 0.3,  blue: 0.75).opacity(0.15), location: 0.5),
                                .init(color: Color(red: 0.1,  green: 0.7,  blue: 0.7 ).opacity(0.5), location: 0.75),
                                .init(color: Color(red: 0.2,  green: 0.85, blue: 1.0 ).opacity(0.6), location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.8
                    )
                )
            HStack(spacing: 0) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .font(.system(.body))
                    .foregroundStyle(.white.opacity(0.88))
                    .focused($focused)
                    .onSubmit { if canSend { onSend() } }
                    .padding(.leading, 18)
                    .padding(.trailing, 6)
                HStack(spacing: 4) {
                    Button(action: onRefine) {
                        if isRefining {
                            ProgressView().scaleEffect(0.55).frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 14))
                                .foregroundStyle(canSend && !isStreaming
                                    ? Color(red: 0.7, green: 0.45, blue: 1)
                                    : .white.opacity(0.18))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canSend || isStreaming)

                    if isStreaming {
                        Button(action: onStop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.85))
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.red.opacity(0.12)))
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button(action: onSend) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(canSend ? .white.opacity(0.9) : .white.opacity(0.18))
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(canSend
                                    ? Color.white.opacity(0.12)
                                    : Color.clear))
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canSend)
                    }
                }
                .padding(.trailing, 8)
            }
        }
        .frame(height: 46)
    }
}

// MARK: - Glass message bubble

struct GlassMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == "user" { Spacer(minLength: 55) }
            Text(message.content)
                .textSelection(.enabled)
                .font(.system(.callout))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
            if message.role != "user" { Spacer(minLength: 55) }
        }
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(message.role == "user"
                ? Color(red: 0.22, green: 0.30, blue: 0.62).opacity(0.85)
                : Color(white: 0.13).opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        message.role == "user"
                            ? Color(red: 0.4, green: 0.5, blue: 1).opacity(0.3)
                            : Color.white.opacity(0.07),
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Pill tab strip (Settings, Extensions, …)

struct PillTabStrip: View {
    let tabs: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab)
                        .font(.system(.caption, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? .white.opacity(0.9) : .white.opacity(0.4))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(selection == tab ? Color.white.opacity(0.1) : Color.clear)
                        )
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var selectedTab = "Paths"

    private let tabs = ["Paths", "Server"]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — same vertical inset as sidebar.left / sidebar.right (mainPanel)
            PillTabStrip(tabs: tabs, selection: $selectedTab)
                .padding(.horizontal, 46)
                .padding(.top, 10)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if selectedTab == "Paths" {
                        settingsSection("Paths") {
                            pathRow("llama-server", text: $settings.serverBinaryPath)
                            Divider().opacity(0.15)
                            pathRow("Model", text: $settings.modelPath)
                        }
                    } else {
                        settingsSection("Server") {
                            numberRow("Port", value: $settings.port)
                            Divider().opacity(0.15)
                            numberRow("Context size", value: $settings.contextSize)
                            Divider().opacity(0.15)
                            numberRow("GPU layers", value: $settings.gpuLayers)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                content()
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        }
        .padding(.bottom, 16)
    }

    private func pathRow(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption))
                .foregroundStyle(.white.opacity(0.5))
            TextField("", text: text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textFieldStyle(.plain)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(.callout))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            TextField("", value: value, format: .number)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Server control popover

struct ServerControlView: View {
    @ObservedObject private var server = LlamaServer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.9), radius: 4)
                    .frame(width: 18)
                Text(statusLabel)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 160)
        .padding(.bottom, 8)
    }

    private var statusColor: Color {
        switch server.state {
        case .stopped:  return .white.opacity(0.25)
        case .starting: return .yellow
        case .running:  return Color(red: 0.15, green: 1, blue: 0.45)
        case .failed:   return .red
        }
    }

    private var statusLabel: String {
        switch server.state {
        case .stopped:  return "Stopped"
        case .starting: return "Starting…"
        case .running:  return "Running"
        case .failed:   return "Failed"
        }
    }

}

// MARK: - Appearance popover

struct AppearanceView: View {
    @ObservedObject private var config = HolosConfig.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                appearanceSection("Background") {
                    HStack {
                        Toggle("Blur", isOn: $config.blurEnabled)
                            .font(.system(.callout))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    Divider().opacity(0.15)
                    appearanceSlider("Blur strength",  value: $config.blurStrength,      in: 0.0...1.0)
                    Divider().opacity(0.15)
                    appearanceSlider("Opacity",        value: $config.backgroundOpacity, in: 0.0...0.95)
                }
                appearanceSection("Glow") {
                    HStack {
                        Text("Style")
                            .font(.system(.callout))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Picker("", selection: $config.glowStyle) {
                            ForEach(GlowStyle.allCases, id: \.self) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    if config.glowStyle == .solidColor {
                        Divider().opacity(0.15)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(red: config.glowColorR, green: config.glowColorG, blue: config.glowColorB))
                            .frame(height: 22)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        Divider().opacity(0.15)
                        colorSlider("R", value: $config.glowColorR, tint: .red)
                        Divider().opacity(0.15)
                        colorSlider("G", value: $config.glowColorG, tint: .green)
                        Divider().opacity(0.15)
                        colorSlider("B", value: $config.glowColorB, tint: .blue)
                    }
                    if config.glowStyle != .off {
                        Divider().opacity(0.15)
                        appearanceSlider("Intensity", value: $config.glowIntensity, in: 0.0...3.0)
                        Divider().opacity(0.15)
                        appearanceSlider("Size",      value: $config.glowSize,      in: 2.0...40.0)
                        Divider().opacity(0.15)
                        appearanceSlider("Blur",      value: $config.glowBlur,      in: 1.0...30.0)
                    }
                }
            }
            .padding(12)

            Button("Reset to defaults") {
                config.backgroundOpacity = 0.18
                config.blurEnabled       = true
                config.blurStrength      = 0.3
                config.glowStyle         = .mimicBorder
                config.glowColorR        = 0.55
                config.glowColorG        = 0.25
                config.glowColorB        = 0.95
                config.glowIntensity     = 1.0
                config.glowSize          = 10.0
                config.glowBlur          = 7.0
            }
            .font(.system(.caption))
            .foregroundStyle(.white.opacity(0.35))
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func colorSlider(_ label: String, value: Binding<Double>, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(tint.opacity(0.7))
                .frame(width: 12)
            Slider(value: value, in: 0...1)
                .tint(tint)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func appearanceSlider(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(.caption))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Slider(value: value, in: range)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func appearanceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Visual effect background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .vibrantDark)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Window reader

class _WindowCapture: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window { onWindow?(w) }
    }
}

struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> _WindowCapture {
        let v = _WindowCapture()
        v.onWindow = onWindow
        return v
    }
    func updateNSView(_ nsView: _WindowCapture, context: Context) {}
}

// MARK: - Log window

struct LogView: View {
    @ObservedObject private var server = LlamaServer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(server.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(8)
                }
                .onChange(of: server.log.count) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
            Divider()
            HStack {
                Button("Clear") { server.clearLog() }
                Spacer()
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Navigation state

final class NavigationState: ObservableObject {
    static let shared = NavigationState()
    private init() {}
    @Published var selectedTab: String = "Chats"
    @Published var globalTab: String? = nil
}

// MARK: - Sidebar content

private enum SidebarCategory: String, CaseIterable, Hashable {
    case ai             = "AI"
    case development    = "Development"
    case versionControl = "Version Control"
    case system         = "System"
    case sound          = "Sound"

    private static let tabOrderDefaultsKey = "holos.sidebarCategoryTabOrder"

    private static var defaultTabOrder: [SidebarCategory] {
        [.ai, .development, .versionControl, .system, .sound]
    }

    static func loadSavedTabOrder() -> [SidebarCategory] {
        guard let raw = UserDefaults.standard.stringArray(forKey: tabOrderDefaultsKey),
              !raw.isEmpty
        else { return defaultTabOrder }
        var seen = Set<String>()
        var result: [SidebarCategory] = []
        for s in raw {
            let normalized = (s == "Music") ? SidebarCategory.sound.rawValue : s
            guard let c = SidebarCategory(rawValue: normalized), seen.insert(c.rawValue).inserted else { continue }
            result.append(c)
        }
        for c in SidebarCategory.allCases where !seen.contains(c.rawValue) {
            result.append(c)
        }
        return result
    }

    static func saveTabOrder(_ order: [SidebarCategory]) {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: tabOrderDefaultsKey)
    }

    var icon: String {
        switch self {
        case .ai:             return "cpu"
        case .development:    return "hammer.fill"
        case .versionControl: return "arrow.triangle.branch"
        case .system:         return "gearshape"
        case .sound:          return "speaker.wave.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .ai:             return Color(red: 0.55, green: 0.40, blue: 0.90)
        case .development:    return Color(red: 0.40, green: 0.72, blue: 1.00)
        case .versionControl: return Color(red: 0.95, green: 0.52, blue: 0.28)
        case .system:         return Color(red: 0.45, green: 0.88, blue: 0.58)
        case .sound:          return Color(red: 0.95, green: 0.35, blue: 0.55)
        }
    }
}

private enum TabStripCoordinateSpace {
    static let name = "holos.tabStrip"
}

private struct TabStripBoundsKey: PreferenceKey {
    static var defaultValue: [SidebarCategory: CGRect] = [:]
    static func reduce(value: inout [SidebarCategory: CGRect], nextValue: () -> [SidebarCategory: CGRect]) {
        for (k, v) in nextValue() { value[k] = v }
    }
}

private struct SoundSidebarNavItem: Identifiable {
    var id: String { tabId }
    let tabId: String
    let icon: String
    let title: String
    let color: Color
}

struct SidebarContentView: View {
    @ObservedObject private var nav    = NavigationState.shared
    @ObservedObject private var server = LlamaServer.shared
    @ObservedObject private var config = HolosConfig.shared
    @State private var category: SidebarCategory = .ai
    @State private var categoryOrder  = SidebarCategory.loadSavedTabOrder()
    @State private var tabStripBounds: [SidebarCategory: CGRect] = [:]
    @State private var tabCmdDragSourceIndex: Int?
    @State private var tabCmdDragCategory: SidebarCategory?
    @State private var tabCmdDragTranslation: CGFloat = 0
    @State private var tabCmdProposedDropIndex: Int?
    @State private var lastDragLocationInStrip: CGPoint?
    @State private var edgeScrollDir: Int = 0
    @State private var scrollAssistIndex: Int = 0
    /// From `NSScrollView` clip view — reliable during scroll (unlike SwiftUI preferences).
    @State private var sidebarNavClipOffsetY: CGFloat = 0
    @State private var sidebarNavMaxClipOffsetY: CGFloat = 0

    private let tabStripEdgeScrollTimer = Timer.publish(every: 0.11, on: .main, in: .common).autoconnect()

    private let aiNavItems: [(icon: String, label: String, color: Color)] = [
        ("bubble.left.fill",                            "Chats",       Color(red: 0.40, green: 0.70, blue: 1.00)),
        ("cube",                                        "Models",      Color(red: 0.55, green: 0.40, blue: 0.90)),
        ("wrench.and.screwdriver",                      "Tools",       Color(red: 1.00, green: 0.65, blue: 0.30)),
        ("cylinder.split.1x2",                          "Knowledge",   Color(red: 0.90, green: 0.40, blue: 0.50)),
        ("point.3.connected.trianglepath.dotted",       "Connections", Color(red: 0.40, green: 0.85, blue: 0.85)),
        ("sparkles",                                    "Skills",      Color(red: 0.95, green: 0.80, blue: 0.35)),
        ("list.bullet.rectangle",                       "Rules",       Color(red: 0.55, green: 0.85, blue: 0.55)),
        ("point.3.filled.connected.trianglepath.dotted","Map",         Color(red: 0.65, green: 0.50, blue: 0.95)),
        ("gearshape",                                   "Settings",    Color(red: 0.70, green: 0.70, blue: 0.75)),
    ]

    private let globalItems: [(icon: String, label: String, color: Color)] = [
        ("puzzlepiece.extension", "Extensions", Color(red: 0.55, green: 0.75, blue: 1.00)),
        ("square.stack.3d.up.fill", "Modules", Color(red: 0.45, green: 0.82, blue: 0.92)),
        ("gearshape.2",           "Settings",   Color(red: 0.70, green: 0.70, blue: 0.75)),
    ]

    private let soundNavItems: [SoundSidebarNavItem] = [
        SoundSidebarNavItem(
            tabId: "soundMap",
            icon: "point.3.filled.connected.trianglepath.dotted",
            title: "Map",
            color: Color(red: 0.65, green: 0.50, blue: 0.95)
        ),
        SoundSidebarNavItem(
            tabId: "soundMixer",
            icon: "slider.horizontal.3",
            title: "Mixer",
            color: Color(red: 0.95, green: 0.42, blue: 0.52)
        ),
    ]

    private let sidebarNavScrollEdgeEpsilon: CGFloat = 4

    private var sidebarNavCanScroll: Bool {
        sidebarNavMaxClipOffsetY > sidebarNavScrollEdgeEpsilon
    }

    private var sidebarNavShowUpHint: Bool {
        sidebarNavCanScroll && sidebarNavClipOffsetY > sidebarNavScrollEdgeEpsilon
    }

    private var sidebarNavShowDownHint: Bool {
        sidebarNavCanScroll && sidebarNavClipOffsetY < sidebarNavMaxClipOffsetY - sidebarNavScrollEdgeEpsilon
    }

    var body: some View {
        HStack(spacing: 0) {
            LeftSidebarResizeHandle()
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 0) {
                // Category tabs (horizontal scroll only — Cmd-drag to reorder, order persisted)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(categoryTabsForStrip, id: \.self) { cat in
                                let modelIndex = categoryOrder.firstIndex(of: cat) ?? 0
                                sidebarCategoryTab(cat: cat, modelIndex: modelIndex)
                                    .id(cat)
                            }
                        }
                        .padding(.horizontal, 10)
                        .coordinateSpace(name: TabStripCoordinateSpace.name)
                    }
                    .onPreferenceChange(TabStripBoundsKey.self) { tabStripBounds = $0 }
                    .scrollDisabled(tabCmdDragSourceIndex != nil)
                    .onReceive(tabStripEdgeScrollTimer) { _ in
                        guard tabCmdDragSourceIndex != nil else { return }
                        updateTabStripEdgeScrollIntent()
                        if let x = lastDragLocationInStrip?.x {
                            proposeDropIfNeeded(pointerX: x)
                        }
                        guard edgeScrollDir != 0 else { return }
                        let strip = categoryTabsForStrip
                        let n = strip.count
                        guard n > 1 else { return }
                        if edgeScrollDir < 0 {
                            scrollAssistIndex = max(0, scrollAssistIndex - 1)
                            let cat = strip[scrollAssistIndex]
                            withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(cat, anchor: .leading) }
                        } else {
                            scrollAssistIndex = min(n - 1, scrollAssistIndex + 1)
                            let cat = strip[scrollAssistIndex]
                            withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(cat, anchor: .trailing) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider().opacity(0.12)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Nav items per category
                        if category == .ai {
                            ForEach(aiNavItems, id: \.label) { item in
                                sidebarRow(icon: item.icon, label: item.label, color: item.color,
                                           isSelected: nav.globalTab == nil && nav.selectedTab == item.label) {
                                    nav.globalTab = nil
                                    nav.selectedTab = item.label
                                }
                            }
                        } else if category == .sound {
                            ForEach(soundNavItems) { item in
                                sidebarRow(icon: item.icon, label: item.title, color: item.color,
                                           isSelected: nav.globalTab == nil && nav.selectedTab == item.tabId) {
                                    nav.globalTab = nil
                                    nav.selectedTab = item.tabId
                                }
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 28))
                                    .foregroundStyle(category.color.opacity(0.5))
                                Text(category.rawValue)
                                    .font(.system(.callout, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text("Coming soon")
                                    .font(.system(.caption))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }

                        MacScrollViewChrome(
                            clipOffsetY: $sidebarNavClipOffsetY,
                            maxClipOffsetY: $sidebarNavMaxClipOffsetY
                        )
                        .frame(width: 0, height: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .overlay(alignment: .top) {
                    sidebarScrollHintChevron(up: true)
                        .opacity(sidebarNavShowUpHint ? 1 : 0)
                        .animation(.easeInOut(duration: 0.18), value: sidebarNavShowUpHint)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    sidebarScrollHintChevron(up: false)
                        .opacity(sidebarNavShowDownHint ? 1 : 0)
                        .animation(.easeInOut(duration: 0.18), value: sidebarNavShowDownHint)
                        .allowsHitTesting(false)
                }
                .frame(minHeight: 0, maxHeight: .infinity)

                Divider().opacity(0.12)
                    .padding(.top, 8)

                // Global items
                VStack(spacing: 0) {
                    ForEach(globalItems, id: \.label) { item in
                        sidebarRow(icon: item.icon, label: item.label, color: item.color,
                                   isSelected: nav.globalTab == item.label) {
                            nav.globalTab = item.label
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            Group {
                if config.blurEnabled {
                    Color.black.opacity(config.backgroundOpacity)
                } else {
                    Color(white: 0.08).opacity(0.95)
                }
            }
            .ignoresSafeArea()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
        )
        .preferredColorScheme(.dark)
    }

    /// Live preview order while ⌘-dragging (neighbors animate via `withAnimation` on `tabCmdProposedDropIndex`).
    private var categoryTabsForStrip: [SidebarCategory] {
        guard let from = tabCmdDragSourceIndex,
              let to = tabCmdProposedDropIndex,
              from != to
        else { return categoryOrder }
        return Self.applyMove(categoryOrder, from: from, to: to)
    }

    private static func applyMove(_ order: [SidebarCategory], from: Int, to: Int) -> [SidebarCategory] {
        guard from >= 0, from < order.count, to >= 0, to < order.count, from != to else { return order }
        var a = order
        let item = a.remove(at: from)
        a.insert(item, at: min(to, a.count))
        return a
    }

    /// Final index of the dragged tab after a move, from pointer X in `TabStripCoordinateSpace` and per-tab bounds.
    private static func finalIndexAfterPointer(
        pointerX: CGFloat,
        from: Int,
        bounds: [SidebarCategory: CGRect],
        categoryOrder: [SidebarCategory]
    ) -> Int {
        guard from >= 0, from < categoryOrder.count else { return 0 }
        let dragged = categoryOrder[from]
        let others = categoryOrder.enumerated().compactMap { $0.offset == from ? nil : $0.element }
        let sortedOthers = others.filter { bounds[$0] != nil }.sorted { bounds[$0]!.minX < bounds[$1]!.minX }
        guard sortedOthers.count == others.count, !sortedOthers.isEmpty else { return from }

        var insertSlot = sortedOthers.count
        for (i, c) in sortedOthers.enumerated() {
            if pointerX < bounds[c]!.midX {
                insertSlot = i
                break
            }
        }

        var arr = categoryOrder
        arr.remove(at: from)
        if insertSlot >= sortedOthers.count {
            arr.append(dragged)
        } else {
            let before = sortedOthers[insertSlot]
            if let ix = arr.firstIndex(of: before) {
                arr.insert(dragged, at: ix)
            } else {
                arr.append(dragged)
            }
        }
        return arr.firstIndex(of: dragged) ?? from
    }

    private func proposeDropIfNeeded(pointerX: CGFloat) {
        guard let from = tabCmdDragSourceIndex else { return }
        let newTo = Self.finalIndexAfterPointer(
            pointerX: pointerX,
            from: from,
            bounds: tabStripBounds,
            categoryOrder: categoryOrder
        )
        guard newTo != tabCmdProposedDropIndex else { return }
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
            tabCmdProposedDropIndex = newTo
        }
    }

    private func updateTabStripEdgeScrollIntent() {
        guard let sf = PinManager.shared.sidebarPanelFrame else {
            edgeScrollDir = 0
            return
        }
        let p = NSEvent.mouseLocation
        let margin: CGFloat = 32
        if p.x < sf.minX + margin {
            edgeScrollDir = -1
        } else if p.x > sf.maxX - margin {
            edgeScrollDir = 1
        } else {
            edgeScrollDir = 0
        }
    }

    private func sidebarCategoryTab(cat: SidebarCategory, modelIndex: Int) -> some View {
        let isDraggingThis = tabCmdDragCategory == cat
        return VStack(spacing: 3) {
            Image(systemName: cat.icon)
                .font(.system(size: 12, weight: .semibold))
            Text(cat.rawValue)
                .font(.system(size: 8.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 72)
        }
        .foregroundStyle(category == cat ? cat.color : .white.opacity(0.35))
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(category == cat ? cat.color.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(category == cat ? cat.color : Color.clear, lineWidth: 0.75)
                )
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabStripBoundsKey.self,
                    value: [cat: geo.frame(in: .named(TabStripCoordinateSpace.name))]
                )
            }
        )
        .fixedSize(horizontal: true, vertical: false)
        .zIndex(isDraggingThis ? 2 : 0)
        .offset(x: isDraggingThis ? tabCmdDragTranslation : 0)
        .opacity(isDraggingThis ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) { category = cat }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(TabStripCoordinateSpace.name))
                .onChanged { value in
                    guard NSEvent.modifierFlags.contains(.command) else { return }
                    if tabCmdDragSourceIndex == nil {
                        tabCmdDragSourceIndex = modelIndex
                        tabCmdDragCategory = cat
                        tabCmdProposedDropIndex = modelIndex
                        scrollAssistIndex = categoryTabsForStrip.firstIndex(of: cat) ?? modelIndex
                    }
                    guard tabCmdDragSourceIndex == modelIndex else { return }
                    tabCmdDragTranslation = value.translation.width
                    lastDragLocationInStrip = value.location
                    proposeDropIfNeeded(pointerX: value.location.x)
                    updateTabStripEdgeScrollIntent()
                }
                .onEnded { _ in
                    guard tabCmdDragSourceIndex == modelIndex else { return }
                    let from = tabCmdDragSourceIndex!
                    let to = tabCmdProposedDropIndex ?? from
                    defer {
                        tabCmdDragSourceIndex = nil
                        tabCmdDragCategory = nil
                        tabCmdDragTranslation = 0
                        tabCmdProposedDropIndex = nil
                        lastDragLocationInStrip = nil
                        edgeScrollDir = 0
                    }
                    guard from != to else { return }
                    let next = Self.applyMove(categoryOrder, from: from, to: to)
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        categoryOrder = next
                    }
                    SidebarCategory.saveTabOrder(next)
                }
        )
    }

    private func sidebarRow(icon: String, label: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? color : color.opacity(0.45))
                    .frame(width: 18)
                Text(label)
                    .font(.system(.callout))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? color : Color.clear, lineWidth: 0.75)
                    )
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func sidebarScrollHintChevron(up: Bool) -> some View {
        Image(systemName: up ? "chevron.compact.up" : "chevron.compact.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.42))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
    }
}

// MARK: - Right context

enum RightContext: String, CaseIterable, Identifiable, Hashable {
    case codeEditor
    case textEditor
    case terminal

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .codeEditor: return "curlybraces"
        case .textEditor: return "text.alignleft"
        case .terminal:   return "terminal"
        }
    }

    var label: String {
        switch self {
        case .codeEditor: return "Code Editor"
        case .textEditor: return "Text Editor"
        case .terminal:   return "Terminal"
        }
    }
}

@MainActor
final class RightSidebarState: ObservableObject {
    static let shared = RightSidebarState()
    private init() {}
    @Published var context: RightContext = .codeEditor
    @Published var showEmbeddedExplorer: Bool = false
    @Published var autoReload: Bool = false {
        didSet {
            autoReload ? CodeEditorModel.shared.startWatching()
                       : CodeEditorModel.shared.stopWatching()
        }
    }
}

// MARK: - Right sidebar

struct RightSidebarContentView: View {
    @ObservedObject private var rightState = RightSidebarState.shared
    @ObservedObject private var config     = HolosConfig.shared

    var body: some View {
        HStack(spacing: 0) {
            content
            SidebarResizeHandle().frame(width: 6)
        }
        .background(
            Group {
                if config.blurEnabled {
                    Color.black.opacity(config.backgroundOpacity)
                } else {
                    Color(white: 0.08).opacity(0.95)
                }
            }
            .ignoresSafeArea()
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
        )
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch rightState.context {
        case .codeEditor: CodeEditorPane()
        case .textEditor: TextEditorPane()
        case .terminal:   TerminalPane()
        }
    }
}

private struct SidebarResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleNSView { ResizeHandleNSView() }
    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {}
}

final class ResizeHandleNSView: NSView {
    private var dragStartScreenX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingArea.map { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.push()
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
        layer?.backgroundColor = .clear
    }

    override func mouseDown(with event: NSEvent) {
        guard let screenPoint = window?.convertToScreen(
            NSRect(origin: event.locationInWindow, size: .zero)
        ).origin else { return }
        dragStartScreenX = screenPoint.x
        dragStartWidth   = PinManager.shared.rightSidebarW
        wantsLayer = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let screenPoint = window?.convertToScreen(
            NSRect(origin: event.locationInWindow, size: .zero)
        ).origin else { return }
        let delta = screenPoint.x - dragStartScreenX
        PinManager.shared.resizeRightSidebar(to: dragStartWidth + delta)
    }

    override func mouseUp(with event: NSEvent) {}

    override var intrinsicContentSize: NSSize { NSSize(width: 6, height: NSView.noIntrinsicMetric) }
}

private struct LeftSidebarResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> LeftSidebarResizeHandleNSView { LeftSidebarResizeHandleNSView() }
    func updateNSView(_ nsView: LeftSidebarResizeHandleNSView, context: Context) {}
}

/// Drag the outer (leading) edge: drag right narrows the sidebar, drag left widens it.
final class LeftSidebarResizeHandleNSView: NSView {
    private var dragStartScreenX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingArea.map { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.push()
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
        layer?.backgroundColor = .clear
    }

    override func mouseDown(with event: NSEvent) {
        guard let screenPoint = window?.convertToScreen(
            NSRect(origin: event.locationInWindow, size: .zero)
        ).origin else { return }
        dragStartScreenX = screenPoint.x
        dragStartWidth   = PinManager.shared.sidebarW
        wantsLayer = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let screenPoint = window?.convertToScreen(
            NSRect(origin: event.locationInWindow, size: .zero)
        ).origin else { return }
        let delta = screenPoint.x - dragStartScreenX
        PinManager.shared.resizeLeftSidebar(to: dragStartWidth - delta)
    }

    override func mouseUp(with event: NSEvent) {}

    override var intrinsicContentSize: NSSize { NSSize(width: 6, height: NSView.noIntrinsicMetric) }
}

private struct CodeEditorPane: View {
    @ObservedObject private var model      = CodeEditorModel.shared
    @ObservedObject private var rightState = RightSidebarState.shared
    @State private var showingExplorer     = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                if rightState.showEmbeddedExplorer {
                    RightContextPickerButton()
                        .frame(width: 180)
                        .frame(maxHeight: .infinity)
                    Divider().opacity(0.12)
                }

                HStack(spacing: 8) {
                    if !rightState.showEmbeddedExplorer { RightContextPickerButton() }
                    Text(rightState.context.label)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    filePickerButton
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)

            Divider().opacity(0.12)

            // Content row
            HStack(spacing: 0) {
                if rightState.showEmbeddedExplorer {
                    FileExplorerView(onSelect: { item in model.open(item) },
                                     selectedURL: model.openFile)
                        .frame(width: 180)
                        .background(Color.white.opacity(0.02))
                    Divider().opacity(0.12)
                }
                CodeEditorView(text: $model.code, language: model.language)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private var filePickerButton: some View {
        Button { showingExplorer.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                Text(model.openFile?.lastPathComponent ?? "Open…")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showingExplorer, arrowEdge: .bottom) {
            FileExplorerView(onSelect: { item in
                model.open(item)
                showingExplorer = false
            }, selectedURL: model.openFile)
            .frame(width: 260, height: 380)
            .preferredColorScheme(.dark)
        }
        .contextMenu {
            Button("Save") { model.save() }
                .disabled(model.openFile == nil)
            Button("Save As…") { model.saveAs() }

            Divider()

            Button("Reload") { model.reload() }
                .disabled(model.openFile == nil)
            Toggle("Auto Reload", isOn: $rightState.autoReload)
                .disabled(model.openFile == nil)

            Divider()

            Toggle("Show Explorer", isOn: $rightState.showEmbeddedExplorer)
        }
    }
}

// MARK: - Shared right pane context picker button

private struct RightContextPickerButton: View {
    @ObservedObject private var rightState = RightSidebarState.shared
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: rightState.context.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(RightContext.allCases) { ctx in
                    Button {
                        rightState.context = ctx
                        showingPicker = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: ctx.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(ctx == rightState.context ? .white.opacity(0.9) : .white.opacity(0.45))
                                .frame(width: 18)
                            Text(ctx.label)
                                .font(.system(.callout))
                                .foregroundStyle(ctx == rightState.context ? .white.opacity(0.9) : .white.opacity(0.55))
                            Spacer(minLength: 8)
                            if ctx == rightState.context {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .frame(minWidth: 200)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Text editor pane

private struct TextEditorPane: View {
    @ObservedObject private var rightState = RightSidebarState.shared
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                RightContextPickerButton()
                Text(rightState.context.label)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.12)

            TextEditor(text: $text)
                .font(.system(.body))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Terminal pane

private struct TerminalPane: View {
    @ObservedObject private var rightState = RightSidebarState.shared
    @State private var lines: [String] = [
        "Holos terminal — no shell session yet.",
        "Lines echo locally; type `clear` to reset the buffer.",
        "",
    ]
    @State private var input = ""

    private let termGreen = Color(red: 0.38, green: 0.92, blue: 0.48)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RightContextPickerButton()
                Text(rightState.context.label)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(termGreen.opacity(line.isEmpty ? 0.2 : 0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("termBottom")
                    }
                    .padding(10)
                }
                .onChange(of: lines.count) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("termBottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.04, green: 0.07, blue: 0.05))

            Divider().opacity(0.12)

            HStack(alignment: .center, spacing: 6) {
                Text("%")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(termGreen.opacity(0.75))
                TextField("", text: $input, axis: .horizontal)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(termGreen)
                    .onSubmit(commitInput)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private func commitInput() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        guard !t.isEmpty else { return }
        if t == "clear" {
            lines = [
                "Buffer cleared.",
                "",
            ]
            return
        }
        lines.append("% \(t)")
        lines.append(t)
        lines.append("")
    }
}
