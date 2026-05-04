import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Shortcuts tab (Global Settings)

struct ShortcutsSettingsContent: View {
    @ObservedObject private var registry = ShortcutRegistry.shared
    @ObservedObject private var store = UserShortcutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let groups = registry.groupedVisibleDefinitions()
            if groups.isEmpty {
                Text("No shortcuts are available for the current modules and extensions.")
                    .font(.system(.callout))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    shortcutSettingsSection(group.section) {
                        ForEach(group.items) { def in
                            shortcutRow(def)
                        }
                    }
                }
            }

            Button("Reset shortcuts to defaults") {
                store.resetToDefaults()
                ShortcutHotKeyController.shared.rebuild()
            }
            .font(.system(.caption))
            .foregroundStyle(.white.opacity(0.35))
            .buttonStyle(.borderless)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
    }

    private func shortcutSettingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func shortcutRow(_ def: ShortcutDefinition) -> some View {
        HStack {
            Text(def.title)
                .font(.system(.callout))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            ShortcutKeyRecorderRow(definition: def)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Key recorder row

private struct ShortcutKeyRecorderRow: View {
    let definition: ShortcutDefinition
    @ObservedObject private var registry = ShortcutRegistry.shared
    @ObservedObject private var store = UserShortcutStore.shared
    @State private var isRecording = false

    private var resolvedText: String {
        if isRecording { return "Press keys…" }
        if let b = registry.effectiveBinding(for: definition) {
            return KeyBindingDisplay.string(for: b)
        }
        return "None"
    }

    var body: some View {
        ShortcutKeyRecorderRepresentable(
            labelText: resolvedText,
            isRecording: isRecording,
            onBeginRecording: {
                isRecording = true
            },
            onCommitBinding: { binding in
                store.setBinding(binding, for: definition.id)
                ShortcutHotKeyController.shared.rebuild()
                isRecording = false
            },
            onClearOverride: {
                store.setBinding(nil, for: definition.id)
                ShortcutHotKeyController.shared.rebuild()
                isRecording = false
            },
            onCancelRecording: {
                isRecording = false
            }
        )
        .frame(width: 168, height: 26)
    }
}

// MARK: - AppKit control

private struct ShortcutKeyRecorderRepresentable: NSViewRepresentable {
    let labelText: String
    let isRecording: Bool
    let onBeginRecording: () -> Void
    let onCommitBinding: (KeyBinding) -> Void
    let onClearOverride: () -> Void
    let onCancelRecording: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let coord = context.coordinator
        let v = ShortcutRecorderNSView()
        v.onMouseDown = {
            coord.parent.onBeginRecording()
        }
        v.onKeyEventWhileRecording = { event in
            coord.handleKey(event)
        }
        return v
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        context.coordinator.parent = self
        nsView.recordingSyncedFromSwiftUI = isRecording
        nsView.label.stringValue = labelText
        nsView.label.textColor = isRecording
            ? NSColor.white.withAlphaComponent(0.45)
            : NSColor.white.withAlphaComponent(0.78)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: ShortcutKeyRecorderRepresentable

        init(parent: ShortcutKeyRecorderRepresentable) {
            self.parent = parent
        }

        func handleKey(_ event: NSEvent) {
            let code = event.keyCode
            if code == UInt16(kVK_Escape) {
                parent.onCancelRecording()
                return
            }
            if code == UInt16(kVK_Delete) || code == UInt16(kVK_ForwardDelete) {
                parent.onClearOverride()
                return
            }
            guard let binding = KeyBinding(event: event), binding.isValidForRegistration else { return }
            parent.onCommitBinding(binding)
        }
    }
}

private final class ShortcutRecorderNSView: NSView {
    let label = NSTextField(labelWithString: "")
    var onMouseDown: (() -> Void)?
    var onKeyEventWhileRecording: ((NSEvent) -> Void)?
    /// Drives `keyDown` routing; SwiftUI is source of truth after the first click.
    var recordingSyncedFromSwiftUI = false

    private var isRecordingMode: Bool { recordingSyncedFromSwiftUI }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor

        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if isRecordingMode {
            onKeyEventWhileRecording?(event)
        } else {
            super.keyDown(with: event)
        }
    }
}
