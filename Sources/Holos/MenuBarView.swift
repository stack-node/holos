import SwiftUI
import AppKit

// MARK: - Main view

struct MenuBarView: View {
    @ObservedObject private var server     = LlamaServer.shared
    @ObservedObject private var chat       = ChatClient.shared
    @ObservedObject private var config     = HolosConfig.shared
    @ObservedObject private var pinManager = PinManager.shared
    @ObservedObject private var settings   = Settings.shared
    @State private var inputText = ""
    @State private var edgePhase: CGFloat = 0
    @State private var isHoveringLeft   = false
    @State private var showingLog       = false
    @State private var showingAppearance = false
    @State private var showingModels    = false
    @ObservedObject private var rightState = RightSidebarState.shared
    var body: some View {
        mainPanel
        .frame(minWidth: 240, idealWidth: 380, minHeight: 240, idealHeight: 500)
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
                    if pinManager.isMinimal {
                        minimalMessagesOverlay
                    } else {
                        messagesArea
                    }
                    inputSection
                } else {
                    placeholderPage(for: nav.selectedTab)
                }
            }

            // Model badge — top center, tappable, opens model selector
            if !pinManager.isMinimal {
                Button { showingModels.toggle() } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                            .shadow(color: statusColor.opacity(0.8), radius: 3)
                        Text(modelDisplayName)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingModels, arrowEdge: .bottom) {
                    ModelSelectorView()
                        .frame(width: 280)
                        .preferredColorScheme(.dark)
                }
                .padding(.top, 10)
                .padding(.horizontal, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            // Left strip: all hover-only controls
            ZStack(alignment: .top) {
                Color.clear
                if isHoveringLeft || showingLog || showingAppearance {
                    VStack(spacing: 16) {
                        iconButton(pinManager.isMinimal ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                                   active: pinManager.isMinimal) {
                            pinManager.isMinimal.toggle()
                        }
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

// Sidebar toggles — topmost layer, receive taps
            if !pinManager.isMinimal {
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
                .padding(.top, 10)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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
                .padding(.top, 10)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
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

    private func placeholderPage(for tab: String) -> some View {
        if tab == "Settings" {
            return AnyView(SettingsView().frame(maxWidth: .infinity, maxHeight: .infinity))
        }
        let meta: (icon: String, color: Color) = {
            switch tab {
            case "Models":      return ("cube",                                Color(red: 0.5, green: 0.4, blue: 1.0))
            case "Prompts":     return ("doc.text",                            Color(red: 0.3, green: 0.7, blue: 0.9))
            case "Tools":       return ("wrench.and.screwdriver",              Color(red: 0.9, green: 0.6, blue: 0.2))
            case "Knowledge":   return ("cylinder.split.1x2",                  Color(red: 0.3, green: 0.8, blue: 0.5))
            case "MCP Servers": return ("point.3.connected.trianglepath.dotted",Color(red: 0.8, green: 0.3, blue: 0.7))
            default:            return ("square.dashed",                       Color.white)
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

    private func globalPlaceholderPage(for tab: String) -> some View {
        if tab == "Extensions" {
            return AnyView(ExtensionListView().frame(maxWidth: .infinity, maxHeight: .infinity))
        }
        let meta: (icon: String, color: Color) = {
            switch tab {
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

    // MARK: Minimal overlay (last 3 bubbles, no scrollview)

    private var minimalMessagesOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            let recent = Array(chat.messages.suffix(3))
            ForEach(recent) { msg in
                GlassMessageBubble(message: msg)
            }
            if chat.isStreaming && !chat.streamingResponse.isEmpty {
                GlassMessageBubble(
                    message: ChatMessage(role: "assistant", content: chat.streamingResponse)
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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


    private var modelDisplayName: String {
        let raw = settings.modelPath
        guard !raw.isEmpty else { return "no model" }
        return URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
    }

    private var statusColor: Color {
        switch server.state {
        case .stopped:  return .white.opacity(0.25)
        case .starting: return .yellow
        case .running:  return Color(red: 0.15, green: 1, blue: 0.45)
        case .failed:   return .red
        }
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

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var selectedTab = "Paths"

    private let tabs = ["Paths", "Server"]

    var body: some View {
        VStack(spacing: 0) {
            // Top chrome clearance + tab bar
            VStack(spacing: 0) {
                Spacer().frame(height: 52)
                HStack(spacing: 4) {
                    ForEach(tabs, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab)
                                .font(.system(.caption, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? .white.opacity(0.9) : .white.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
                                )
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

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

// MARK: - Model selector popover

struct ModelEntry: Identifiable {
    let id = UUID()
    var name: String
    var status: ModelEntryStatus
    var isActive: Bool
}

enum ModelEntryStatus {
    case running, stopped, loading, failed

    var color: Color {
        switch self {
        case .running: return Color(red: 0.15, green: 1, blue: 0.45)
        case .stopped: return .white.opacity(0.25)
        case .loading: return .yellow
        case .failed:  return .red
        }
    }

    var label: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .loading: return "Loading"
        case .failed:  return "Failed"
        }
    }
}

struct ModelSelectorView: View {
    @ObservedObject private var server   = LlamaServer.shared
    @ObservedObject private var settings = Settings.shared

    private var models: [ModelEntry] {
        let active = URL(fileURLWithPath: settings.modelPath)
            .deletingPathExtension().lastPathComponent
        let activeStatus: ModelEntryStatus = {
            switch server.state {
            case .running:  return .running
            case .starting: return .loading
            case .failed:   return .failed
            case .stopped:  return .stopped
            }
        }()
        return [
            ModelEntry(name: active.isEmpty ? "No model" : active,
                       status: activeStatus, isActive: true),
            ModelEntry(name: "placeholder-model-a", status: .stopped, isActive: false),
            ModelEntry(name: "placeholder-model-b", status: .stopped, isActive: false),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Models")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider().opacity(0.15)

            ForEach(models) { model in
                modelRow(model)
                Divider().opacity(0.15)
            }
        }
        .padding(.bottom, 4)
    }

    private func modelRow(_ model: ModelEntry) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.status.color)
                .frame(width: 6, height: 6)
                .shadow(color: model.status.color.opacity(0.8), radius: 3)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(model.isActive ? .white.opacity(0.9) : .white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.status.label)
                    .font(.system(.caption2))
                    .foregroundStyle(model.status.color.opacity(0.8))
            }
            Spacer()
            if !model.isActive {
                Text("placeholder")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(model.isActive ? Color.white.opacity(0.04) : Color.clear)
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

private enum SidebarCategory: String, CaseIterable {
    case ai    = "AI"
    case music = "Music"

    var icon: String {
        switch self {
        case .ai:    return "cpu"
        case .music: return "music.note"
        }
    }

    var color: Color {
        switch self {
        case .ai:    return Color(red: 0.55, green: 0.40, blue: 0.90)
        case .music: return Color(red: 0.95, green: 0.35, blue: 0.55)
        }
    }
}

struct SidebarContentView: View {
    @ObservedObject private var nav    = NavigationState.shared
    @ObservedObject private var server = LlamaServer.shared
    @ObservedObject private var config = HolosConfig.shared
    @State private var category: SidebarCategory = .ai

    private let aiNavItems: [(icon: String, label: String, color: Color)] = [
        ("bubble.left.fill",                    "Chats",       Color(red: 0.40, green: 0.70, blue: 1.00)),
        ("cube",                                "Models",      Color(red: 0.55, green: 0.40, blue: 0.90)),
        ("doc.text",                            "Prompts",     Color(red: 0.35, green: 0.80, blue: 0.65)),
        ("wrench.and.screwdriver",              "Tools",       Color(red: 1.00, green: 0.65, blue: 0.30)),
        ("cylinder.split.1x2",                  "Knowledge",   Color(red: 0.90, green: 0.40, blue: 0.50)),
        ("point.3.connected.trianglepath.dotted","MCP Servers", Color(red: 0.40, green: 0.85, blue: 0.85)),
        ("gearshape",                           "Settings",    Color(red: 0.70, green: 0.70, blue: 0.75)),
    ]

    private let globalItems: [(icon: String, label: String, color: Color)] = [
        ("puzzlepiece.extension", "Extensions", Color(red: 0.55, green: 0.75, blue: 1.00)),
        ("gearshape.2",           "Settings",   Color(red: 0.70, green: 0.70, blue: 0.75)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category tabs
            HStack(spacing: 6) {
                ForEach(SidebarCategory.allCases, id: \.self) { cat in
                    Button { withAnimation(.easeInOut(duration: 0.18)) { category = cat } } label: {
                        VStack(spacing: 3) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(cat.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(category == cat ? cat.color : .white.opacity(0.35))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(category == cat ? cat.color.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.12)
                .padding(.bottom, 8)

            // Nav items per category
            if category == .ai {
                ForEach(aiNavItems, id: \.label) { item in
                    sidebarRow(icon: item.icon, label: item.label, color: item.color,
                               isSelected: nav.selectedTab == item.label) {
                        nav.selectedTab = item.label
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundStyle(SidebarCategory.music.color.opacity(0.5))
                    Text("Music")
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Coming soon")
                        .font(.system(.caption))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }

            Spacer()

            Divider().opacity(0.12)
                .padding(.top, 8)

            // Global items
            ForEach(globalItems, id: \.label) { item in
                sidebarRow(icon: item.icon, label: item.label, color: item.color,
                           isSelected: nav.globalTab == item.label) {
                    nav.globalTab = nav.globalTab == item.label ? nil : item.label
                }
            }

            Divider().opacity(0.10)

            // Server + power controls
            HStack(spacing: 0) {
                Button {
                    server.isRunning ? server.stop() : server.start()
                } label: {
                    Image(systemName: server.isRunning ? "stop.circle" : "play.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(server.isRunning ? Color.red.opacity(0.75) : Color.green.opacity(0.75))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Divider().opacity(0.12).frame(height: 18)

                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            .frame(height: 38)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Right context

enum RightContext: String, CaseIterable, Identifiable {
    case codeEditor
    case textEditor

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .codeEditor: return "curlybraces"
        case .textEditor: return "text.alignleft"
        }
    }

    var label: String {
        switch self {
        case .codeEditor: return "Code Editor"
        case .textEditor: return "Text Editor"
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
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(showing ? Color.white.opacity(0.12) : Color.white.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: rightState.context.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showing, arrowEdge: .top) {
            VStack(spacing: 0) {
                ForEach(RightContext.allCases) { ctx in
                    Button {
                        rightState.context = ctx
                        showing = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: ctx.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(rightState.context == ctx
                                    ? Color(red: 0.4, green: 0.85, blue: 1.0)
                                    : .white.opacity(0.55))
                                .frame(width: 16)
                            Text(ctx.label)
                                .font(.system(.callout))
                                .foregroundStyle(rightState.context == ctx
                                    ? .white.opacity(0.9)
                                    : .white.opacity(0.55))
                            Spacer()
                            if rightState.context == ctx {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 1.0))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(rightState.context == ctx ? Color.white.opacity(0.05) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    if ctx != RightContext.allCases.last { Divider().opacity(0.12) }
                }
            }
            .frame(minWidth: 160)
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
