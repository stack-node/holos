import Foundation
import Combine

/// Feature modules map 1:1 to sidebar category tabs. **All default to off** — users opt in.
struct ModuleFlags: Codable, Equatable {
    var ai: Bool = false
    var development: Bool = false
    var system: Bool = false
    var sound: Bool = false

    func isEnabled(_ category: SidebarCategory) -> Bool {
        switch category {
        case .ai: return ai
        case .development: return development
        case .system: return system
        case .sound: return sound
        }
    }
}

/// Per–feature toggles inside a category (e.g. AI ▸ Chats). **Defaults off.** AI **Settings** (paths/server) is not stored here.
struct SubmoduleFlags: Codable, Equatable {
    var ai: [String: Bool] = [:]
    var development: [String: Bool] = [:]
    var sound: [String: Bool] = [:]
    var system: [String: Bool] = [:]
}

@MainActor
final class ModuleRegistry: ObservableObject {
    static let shared = ModuleRegistry()

    private static let defaultsKey = "holos.moduleFlags"
    private static let subDefaultsKey = "holos.submoduleFlags"

    @Published private(set) var flags: ModuleFlags
    @Published private(set) var subFlags: SubmoduleFlags

    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(ModuleFlags.self, from: data) {
            flags = decoded
        } else {
            flags = ModuleFlags()
        }

        if let data = UserDefaults.standard.data(forKey: Self.subDefaultsKey),
           let decoded = try? JSONDecoder().decode(SubmoduleFlags.self, from: data) {
            subFlags = Self.mergedSubDefaults(with: decoded)
        } else {
            subFlags = Self.defaultSubmoduleFlags()
        }

        $flags
            .dropFirst()
            .sink { [weak self] _ in
                self?.persist()
                self?.syncInfrastructure()
                DispatchQueue.main.async {
                    NavigationState.shared.sanitizeModuleNavigation()
                    NavigationState.shared.sanitizeSubmoduleNavigation()
                }
            }
            .store(in: &cancellables)

        $subFlags
            .dropFirst()
            .sink { [weak self] _ in
                self?.persistSub()
                DispatchQueue.main.async {
                    NavigationState.shared.sanitizeSubmoduleNavigation()
                }
            }
            .store(in: &cancellables)

        syncAIOnly()
        bootstrapPersistenceIfNeeded()
        DispatchQueue.main.async {
            NavigationState.shared.sanitizeModuleNavigation()
            NavigationState.shared.sanitizeSubmoduleNavigation()
        }
    }

    /// Writes defaults to disk the first time keys are missing so **first launch** is explicitly “all off”,
    /// while upgrades that already have module flags still get submodule JSON saved once.
    private func bootstrapPersistenceIfNeeded() {
        if UserDefaults.standard.object(forKey: Self.defaultsKey) == nil {
            persist()
        }
        if UserDefaults.standard.object(forKey: Self.subDefaultsKey) == nil {
            persistSub()
        }
    }

    private static func defaultSubmoduleFlags() -> SubmoduleFlags {
        var s = SubmoduleFlags()
        for id in SubmoduleCatalog.aiFeatureTabLabels { s.ai[id] = false }
        for ctx in RightContext.allCases { s.development[ctx.rawValue] = false }
        for id in SubmoduleCatalog.soundTabIds { s.sound[id] = false }
        return s
    }

    /// Fill missing keys after decode so new sub-modules get explicit `false`.
    private static func mergedSubDefaults(with stored: SubmoduleFlags) -> SubmoduleFlags {
        var s = stored
        for id in SubmoduleCatalog.aiFeatureTabLabels { s.ai[id] = s.ai[id] ?? false }
        for ctx in RightContext.allCases { s.development[ctx.rawValue] = s.development[ctx.rawValue] ?? false }
        for id in SubmoduleCatalog.soundTabIds { s.sound[id] = s.sound[id] ?? false }
        return s
    }

    func isEnabled(_ category: SidebarCategory) -> Bool {
        flags.isEnabled(category)
    }

    var enabledCategories: [SidebarCategory] {
        SidebarCategory.allCases.filter { flags.isEnabled($0) }
    }

    func setEnabled(_ category: SidebarCategory, _ on: Bool) {
        var next = flags
        switch category {
        case .ai: next.ai = on
        case .development: next.development = on
        case .system: next.system = on
        case .sound: next.sound = on
        }
        guard next != flags else { return }
        flags = next
    }

    /// Feature slice of a category (not used for AI **Settings** — that’s configuration, not a sub-module).
    func isSubEnabled(_ category: SidebarCategory, _ id: String) -> Bool {
        guard isEnabled(category) else { return false }
        switch category {
        case .ai:
            if id == SubmoduleCatalog.aiSettingsTabLabel { return true }
            return subFlags.ai[id] ?? false
        case .development:
            return subFlags.development[id] ?? false
        case .sound:
            return subFlags.sound[id] ?? false
        case .system:
            return subFlags.system[id] ?? false
        }
    }

    func setSubEnabled(_ category: SidebarCategory, _ id: String, _ on: Bool) {
        guard SubmoduleCatalog.ids(for: category).contains(id) else { return }
        guard isEnabled(category) else { return }

        var next = subFlags

        switch category {
        case .ai:
            var d = next.ai
            if !on {
                for dep in SubmoduleCatalog.dependents(for: category, id: id) {
                    d[dep] = false
                }
            }
            d[id] = on
            if on {
                for req in SubmoduleCatalog.hardRequirements(for: category, id: id) where SubmoduleCatalog.aiFeatureTabLabels.contains(req) {
                    d[req] = true
                }
            }
            next.ai = d

        case .development:
            var d = next.development
            if !on {
                for dep in SubmoduleCatalog.dependents(for: category, id: id) {
                    d[dep] = false
                }
            }
            d[id] = on
            if on {
                for req in SubmoduleCatalog.hardRequirements(for: category, id: id) {
                    d[req] = true
                }
            }
            next.development = d

        case .sound:
            var d = next.sound
            if !on {
                for dep in SubmoduleCatalog.dependents(for: category, id: id) {
                    d[dep] = false
                }
            }
            d[id] = on
            if on {
                for req in SubmoduleCatalog.hardRequirements(for: category, id: id) {
                    d[req] = true
                }
            }
            next.sound = d

        case .system:
            var d = next.system
            d[id] = on
            next.system = d
        }

        guard next != subFlags else { return }
        subFlags = next
    }

    /// Valid primary tab for the sidebar when entering or repairing selection (AI includes **Settings**).
    func preferredSelectedTab(for category: SidebarCategory) -> String {
        switch category {
        case .ai:
            if let t = SubmoduleCatalog.aiFeatureTabLabels.first(where: { isSubEnabled(.ai, $0) }) {
                return t
            }
            return SubmoduleCatalog.aiSettingsTabLabel
        case .development:
            return RightContext.allCases.map(\.rawValue).first(where: { isSubEnabled(.development, $0) })
                ?? RightContext.codeEditor.rawValue
        case .sound:
            return SubmoduleCatalog.soundTabIds.first(where: { isSubEnabled(.sound, $0) }) ?? "soundMap"
        case .system:
            return ""
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(flags) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func persistSub() {
        if let data = try? JSONEncoder().encode(subFlags) {
            UserDefaults.standard.set(data, forKey: Self.subDefaultsKey)
        }
    }

    /// AI-only sync safe to call before `ExtensionManager` exists (app launch).
    private func syncAIOnly() {
        if flags.ai {
            LlamaServer.shared.start()
        } else {
            LlamaServer.shared.stop()
            ChatClient.shared.cancel()
            ChatClient.shared.dismissRefinement()
        }
    }

    private func syncInfrastructure() {
        syncAIOnly()
        ExtensionManager.shared.syncSoundModuleWithRegistry()
    }
}
