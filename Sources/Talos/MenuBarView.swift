import SwiftUI
import AppKit

// MARK: - Main view

struct MenuBarView: View {
    @ObservedObject private var server = LlamaServer.shared
    @ObservedObject private var chat   = ChatClient.shared
    @ObservedObject private var config = TalosConfig.shared
    @State private var inputText = ""
    @State private var edgePhase: CGFloat = 0
    @State private var isHovering = false
    @State private var showingSettings = false
    @State private var showingLog = false
    @State private var showingAppearance = false
    @State private var showingStatus = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                messagesArea
                inputSection
            }

            // Right-side strip: dot always visible, icons on hover
            ZStack(alignment: .top) {
                Color.clear
                VStack(spacing: 16) {
                    Button { showingStatus.toggle() } label: {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: statusColor.opacity(0.9), radius: 5)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingStatus, arrowEdge: .leading) {
                        ServerControlView()
                            .preferredColorScheme(.dark)
                    }

                    if isHovering || showingSettings || showingLog || showingAppearance {
                        VStack(spacing: 16) {
                            iconButton("gearshape", active: showingSettings) {
                                showingSettings.toggle(); showingLog = false; showingAppearance = false
                            }
                            .popover(isPresented: $showingSettings, arrowEdge: .leading) {
                                SettingsView()
                                    .frame(width: 320)
                                    .preferredColorScheme(.dark)
                            }

                            iconButton("terminal", active: showingLog) {
                                showingLog.toggle(); showingSettings = false; showingAppearance = false
                            }
                            .popover(isPresented: $showingLog, arrowEdge: .leading) {
                                LogView()
                                    .frame(width: 360, height: 300)
                                    .preferredColorScheme(.dark)
                            }

                            iconButton("paintbrush", active: showingAppearance) {
                                showingAppearance.toggle(); showingSettings = false; showingLog = false
                            }
                            .popover(isPresented: $showingAppearance, arrowEdge: .leading) {
                                AppearanceView()
                                    .frame(width: 280)
                                    .preferredColorScheme(.dark)
                            }

                            iconButton("trash", active: false) { chat.clearHistory() }
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                }
                .padding(.top, 14)
            }
            .frame(width: 36)
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
            }
        }
        .frame(minWidth: 320, idealWidth: 380, minHeight: 380, idealHeight: 500)
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
                            .init(color: Color(red: 0.5,  green: 0.2,  blue: 0.1 ).opacity(0.2), location: 0.5),
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

    @ViewBuilder private var liquidGlassEdge: some View {
        if config.glowEnabled {
        let glow = CGFloat(config.glowSize)
        let blur = CGFloat(config.glowBlur)
        let intensity = config.glowIntensity
        Canvas { ctx, size in
            let r: CGFloat = 12
            let half       = glow * 0.5
            let inner = CGRect(x: half, y: half,
                               width: size.width - glow,
                               height: size.height - glow)
            let path = Path(roundedRect: inner, cornerRadius: max(1, r - half))

            ctx.drawLayer { c in
                c.addFilter(.blur(radius: blur * 0.85))
                c.stroke(path,
                         with: .color(Color(red: 0.55, green: 0.25, blue: 0.95)
                            .opacity((0.18 + edgePhase * 0.07) * intensity)),
                         lineWidth: glow)
            }
            ctx.drawLayer { c in
                c.addFilter(.blur(radius: blur * 1.15))
                c.stroke(path,
                         with: .color(Color(red: 0.9, green: 0.3, blue: 0.6)
                            .opacity((0.12 + edgePhase * 0.05) * intensity)),
                         lineWidth: glow)
            }
            ctx.drawLayer { c in
                c.addFilter(.blur(radius: blur))
                c.stroke(path,
                         with: .color(Color(red: 0.1, green: 0.75, blue: 0.9)
                            .opacity((0.14 + (1 - edgePhase) * 0.06) * intensity)),
                         lineWidth: glow)
            }
        }
        .allowsHitTesting(false)
        }
    }

    private var hairline: some View {
        Color.white.opacity(0.07).frame(height: 0.5)
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
            .padding(.horizontal, 12)
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
            Image(systemName: name).font(.system(size: 12))
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
                                .init(color: Color(red: 0.5,  green: 0.2,  blue: 0.1 ).opacity(0.2), location: 0.5),
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                settingsSection("Paths") {
                    pathRow("llama-server", text: $settings.serverBinaryPath)
                    Divider().opacity(0.15)
                    pathRow("Model", text: $settings.modelPath)
                }
                settingsSection("Server") {
                    numberRow("Port", value: $settings.port)
                    Divider().opacity(0.15)
                    numberRow("Context size", value: $settings.contextSize)
                    Divider().opacity(0.15)
                    numberRow("GPU layers", value: $settings.gpuLayers)
                }
            }
            .padding(12)
        }
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
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.9), radius: 4)
                Text(statusLabel)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.15)

            if server.isRunning {
                controlButton("Stop Server", icon: "stop.circle", color: .red.opacity(0.8)) {
                    server.stop()
                }
            } else {
                controlButton("Start Server", icon: "play.circle", color: .green.opacity(0.8)) {
                    server.start()
                }
            }

            Divider().opacity(0.15)

            controlButton("Quit Talos", icon: "power", color: .white.opacity(0.4)) {
                NSApp.terminate(nil)
            }
        }
        .frame(width: 200)
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

    private func controlButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(label)
                    .font(.system(.callout))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
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
                        Toggle("Enabled", isOn: $config.glowEnabled)
                            .font(.system(.callout))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    Divider().opacity(0.15)
                    appearanceSlider("Intensity", value: $config.glowIntensity, in: 0.0...3.0)
                    Divider().opacity(0.15)
                    appearanceSlider("Size",      value: $config.glowSize,      in: 2.0...40.0)
                    Divider().opacity(0.15)
                    appearanceSlider("Blur",      value: $config.glowBlur,      in: 1.0...30.0)
                }
            }
            .padding(12)

            Button("Reset to defaults") {
                config.backgroundOpacity = 0.18
                config.blurEnabled       = true
                config.blurStrength      = 0.3
                config.glowEnabled       = true
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
