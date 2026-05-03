import SwiftUI
import AppKit

// MARK: - Main view

struct MenuBarView: View {
    @ObservedObject private var server     = LlamaServer.shared
    @ObservedObject private var chat       = ChatClient.shared
    @ObservedObject private var config     = TalosConfig.shared
    @ObservedObject private var pinManager = PinManager.shared
    @ObservedObject private var settings   = Settings.shared
    @State private var inputText = ""
    @State private var edgePhase: CGFloat = 0
    @State private var isHoveringLeft   = false
    @State private var isHoveringRight  = false
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
                if nav.selectedTab == "Chats" {
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

            // Right strip: hover-only context picker
            ZStack(alignment: .top) {
                Color.clear
                if isHoveringRight || pinManager.isRightSidebarOpen {
                    VStack(spacing: 16) {
                        ForEach(RightContext.allCases) { ctx in
                            iconButton(ctx.icon, active: rightState.context == ctx) {
                                rightState.context = ctx
                                if !pinManager.isRightSidebarOpen { pinManager.toggleRightSidebar() }
                            }
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
                withAnimation(.easeInOut(duration: 0.15)) { isHoveringRight = hovering }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

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
                placeholder: "Message Talos",
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
    @ObservedObject private var config = TalosConfig.shared

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
}

// MARK: - Sidebar content

struct SidebarContentView: View {
    @ObservedObject private var nav    = NavigationState.shared
    @ObservedObject private var server = LlamaServer.shared

    private let navItems: [(icon: String, label: String)] = [
        ("bubble.left.fill",                    "Chats"),
        ("cube",                                "Models"),
        ("doc.text",                            "Prompts"),
        ("wrench.and.screwdriver",              "Tools"),
        ("cylinder.split.1x2",                  "Knowledge"),
        ("point.3.connected.trianglepath.dotted","MCP Servers"),
        ("gearshape",                           "Settings"),
    ]

    private let bottomItems: [(icon: String, label: String)] = [
        ("questionmark.circle", "Help"),
        ("bubble.left",         "Feedback"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App header
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Talos")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.12)
                .padding(.bottom, 8)

            // Nav items
            ForEach(navItems, id: \.label) { item in
                sidebarRow(icon: item.icon, label: item.label,
                           isSelected: nav.selectedTab == item.label) {
                    nav.selectedTab = item.label
                }
            }

            Spacer()

            Divider().opacity(0.12)
                .padding(.top, 8)

            // Bottom items
            ForEach(bottomItems, id: \.label) { item in
                sidebarRow(icon: item.icon, label: item.label, isSelected: false) {}
            }

            // User row
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(red: 0.35, green: 0.35, blue: 0.75))
                    Text("U")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
                Text("User")
                    .font(.system(.callout))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

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
        .preferredColorScheme(.dark)
    }

    private func sidebarRow(icon: String, label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .white.opacity(0.45))
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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .codeEditor: return "curlybraces"
        }
    }

    var label: String {
        switch self {
        case .codeEditor: return "Editor"
        }
    }
}

@MainActor
final class RightSidebarState: ObservableObject {
    static let shared = RightSidebarState()
    private init() {}
    @Published var context: RightContext = .codeEditor
}

// MARK: - Right sidebar

struct RightSidebarContentView: View {
    @ObservedObject private var rightState = RightSidebarState.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarResizeHandle()
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch rightState.context {
        case .codeEditor:
            CodeEditorPane()
        }
    }
}

private struct SidebarResizeHandle: View {
    @State private var dragBaseWidth: CGFloat = PinManager.shared.rightSidebarW
    @State private var isHovering = false

    var body: some View {
        Color.white.opacity(isHovering ? 0.08 : 0.0)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.resizeLeftRight.push() }
                else        { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let newWidth = dragBaseWidth - value.translation.width
                        PinManager.shared.resizeRightSidebar(to: newWidth)
                    }
                    .onEnded { _ in
                        dragBaseWidth = PinManager.shared.rightSidebarW
                    }
            )
    }
}

private struct CodeEditorPane: View {
    @State private var code = ""
    @State private var language: CodeLanguage = .swift
    @State private var openFile: URL? = nil
    @State private var showingExplorer = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.12)
            CodeEditorView(text: $code, language: language)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "curlybraces")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text("Editor")
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            filePickerButton
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private var filePickerButton: some View {
        Button {
            showingExplorer.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                Text(openFile?.lastPathComponent ?? "Open…")
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
                if let content = try? String(contentsOf: item.url, encoding: .utf8) {
                    code = content
                    language = item.detectedLanguage()
                    openFile = item.url
                    showingExplorer = false
                }
            }, selectedURL: openFile)
            .frame(width: 260, height: 380)
            .preferredColorScheme(.dark)
        }
    }
}
