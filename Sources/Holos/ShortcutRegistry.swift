import Foundation
import AppKit
import Carbon.HIToolbox
import Combine

// MARK: - Key binding (Carbon-friendly)

/// Stored shortcut; `modifiers` uses Carbon `cmdKey` / `shiftKey` / `optionKey` / `controlKey` bits (see Events.h).
struct KeyBinding: Codable, Equatable, Hashable {
    var keyCode: UInt16
    /// Carbon modifier flags (cmdKey | shiftKey | …).
    var carbonModifiers: UInt32

    init(keyCode: UInt16, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        keyCode = event.keyCode
        carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let f = flags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// Requires at least one modifier (menu-bar global shortcuts should not be bare keys).
    var isValidForRegistration: Bool {
        carbonModifiers != 0
    }
}

// MARK: - Display / parsing helpers

enum KeyBindingDisplay {
    static func string(for binding: KeyBinding) -> String {
        var parts: [String] = []
        let m = binding.carbonModifiers
        if (m & UInt32(cmdKey)) != 0 { parts.append("⌘") }
        if (m & UInt32(shiftKey)) != 0 { parts.append("⇧") }
        if (m & UInt32(optionKey)) != 0 { parts.append("⌥") }
        if (m & UInt32(controlKey)) != 0 { parts.append("⌃") }
        parts.append(keyLabel(for: binding.keyCode))
        return parts.joined()
    }

    private static func keyLabel(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        default:
            return "#\(keyCode)"
        }
    }
}

// MARK: - Source & action

enum ShortcutSource: Equatable, Hashable {
    case core
    case module(category: SidebarCategory, submoduleId: String?)
    case `extension`(extensionId: String)
}

enum ShortcutActionKind: Equatable, Hashable {
    case toggleMainWindow
    case extensionCommand(extensionId: String, action: String)
}

struct ShortcutDefinition: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let source: ShortcutSource
    let kind: ShortcutActionKind
    let defaultBinding: KeyBinding?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ShortcutDefinition, rhs: ShortcutDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - User overrides

@MainActor
final class UserShortcutStore: ObservableObject {
    static let shared = UserShortcutStore()

    private let fileURL: URL
    private var overrides: [String: KeyBinding] = [:]

    private struct Disk: Codable {
        var overrides: [String: KeyBinding]
    }

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holos/configuration")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("shortcuts.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let disk = try? JSONDecoder().decode(Disk.self, from: data)
        else { return }
        overrides = disk.overrides
    }

    private func save() {
        let disk = Disk(overrides: overrides)
        guard let data = try? JSONEncoder().encode(disk) else { return }
        try? data.write(to: fileURL)
    }

    func binding(for shortcutId: String) -> KeyBinding? {
        overrides[shortcutId]
    }

    func setBinding(_ binding: KeyBinding?, for shortcutId: String) {
        if let b = binding {
            overrides[shortcutId] = b
        } else {
            overrides.removeValue(forKey: shortcutId)
        }
        save()
        objectWillChange.send()
    }

    func resetToDefaults() {
        overrides = [:]
        save()
        objectWillChange.send()
    }
}

// MARK: - Registry (definitions + visibility)

@MainActor
final class ShortcutRegistry: ObservableObject {
    static let shared = ShortcutRegistry()

    /// Stable id for the menu-bar window toggle.
    static let toggleWindowShortcutId = "holos.core.toggleWindow"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        UserShortcutStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        ExtensionManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        ModuleRegistry.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .holosExtensionRunStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// ⌘⌃Space — explicit modifiers reduce clashes with common system shortcuts.
    private static let coreDefinitions: [ShortcutDefinition] = [
        ShortcutDefinition(
            id: ShortcutRegistry.toggleWindowShortcutId,
            title: "Toggle Window",
            source: .core,
            kind: .toggleMainWindow,
            defaultBinding: KeyBinding(keyCode: UInt16(kVK_Space), carbonModifiers: UInt32(cmdKey | controlKey))
        ),
    ]

    func allDefinitionsSnapshot() -> [ShortcutDefinition] {
        var list = Self.coreDefinitions
        for ext in ExtensionManager.shared.extensions {
            for spec in ext.manifest.shortcuts {
                let sid = "ext.\(ext.id).\(spec.id)"
                list.append(
                    ShortcutDefinition(
                        id: sid,
                        title: spec.title,
                        source: .extension(extensionId: ext.id),
                        kind: .extensionCommand(extensionId: ext.id, action: spec.action),
                        defaultBinding: spec.defaultBinding
                    )
                )
            }
        }
        return list
    }

    func isVisible(_ definition: ShortcutDefinition) -> Bool {
        switch definition.source {
        case .core:
            return true
        case .module(let category, let submoduleId):
            guard ModuleRegistry.shared.isEnabled(category) else { return false }
            if let sub = submoduleId {
                return ModuleRegistry.shared.isSubEnabled(category, sub)
            }
            return true
        case .extension(let extensionId):
            guard let ext = ExtensionManager.shared.extensions.first(where: { $0.id == extensionId }) else {
                return false
            }
            if case .running = ext.runState { return true }
            return false
        }
    }

    func visibleDefinitions() -> [ShortcutDefinition] {
        allDefinitionsSnapshot().filter { isVisible($0) }
    }

    /// Section title + rows for Settings UI.
    func groupedVisibleDefinitions() -> [(section: String, items: [ShortcutDefinition])] {
        let visible = visibleDefinitions()
        var core: [ShortcutDefinition] = []
        var byExtension: [String: [ShortcutDefinition]] = [:]
        var byModuleTitle: [String: [ShortcutDefinition]] = [:]

        for d in visible {
            switch d.source {
            case .core:
                core.append(d)
            case .extension(let extId):
                byExtension[extId, default: []].append(d)
            case .module(let cat, let sub):
                let title: String
                if let sub {
                    title = SubmoduleCatalog.title(for: cat, id: sub)
                } else {
                    title = cat.rawValue
                }
                byModuleTitle[title, default: []].append(d)
            }
        }

        var sections: [(section: String, items: [ShortcutDefinition])] = []
        if !core.isEmpty {
            sections.append(("Core", core.sorted { $0.title < $1.title }))
        }

        let sortedExtKeys = byExtension.keys.sorted()
        for extId in sortedExtKeys {
            guard let ext = ExtensionManager.shared.extensions.first(where: { $0.id == extId }) else { continue }
            if let items = byExtension[extId] {
                sections.append((ext.manifest.name, items.sorted { $0.title < $1.title }))
            }
        }

        for title in byModuleTitle.keys.sorted() {
            if let items = byModuleTitle[title] {
                sections.append((title, items.sorted { $0.title < $1.title }))
            }
        }

        return sections
    }

    func effectiveBinding(for definition: ShortcutDefinition) -> KeyBinding? {
        if let o = UserShortcutStore.shared.binding(for: definition.id) { return o }
        return definition.defaultBinding
    }
}

extension Notification.Name {
    static let holosExtensionRunStateChanged = Notification.Name("holosExtensionRunStateChanged")
}
