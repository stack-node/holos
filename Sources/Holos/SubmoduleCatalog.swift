import Foundation

/// Identifiers for **sub-modules** (parts of a sidebar category). Settings-style entries (e.g. AI llama paths)
/// are **not** sub-modules — they stay available whenever the parent module is on.
enum SubmoduleCatalog {

    /// AI sidebar rows that can be toggled (excludes **Settings**, which opens AI configuration).
    static let aiFeatureTabLabels: [String] = [
        "Chats", "Models", "Tools", "Knowledge", "Connections", "Skills", "Rules", "Map",
    ]

    static let aiSettingsTabLabel = "Settings"

    static let soundTabIds: [String] = ["soundMap", "soundMixer"]

    static func ids(for category: SidebarCategory) -> [String] {
        switch category {
        case .ai: return aiFeatureTabLabels
        case .development: return RightContext.allCases.map(\.rawValue)
        case .sound: return soundTabIds
        case .system: return []
        }
    }

    /// Human-readable title for Modules UI and hints.
    static func title(for category: SidebarCategory, id: String) -> String {
        switch category {
        case .ai:
            return id
        case .development:
            return RightContext(rawValue: id)?.label ?? id
        case .sound:
            switch id {
            case "soundMap": return "Map"
            case "soundMixer": return "Mixer"
            default: return id
            }
        case .system:
            return id
        }
    }

    /// Other **feature** sub-module ids in the same category that must be on before `id` can be on.
    /// (Example: Chats needs Models.) Settings tabs are not included.
    static func hardRequirements(for category: SidebarCategory, id: String) -> [String] {
        switch category {
        case .ai:
            if id == "Chats" { return ["Models"] }
            return []
        default:
            return []
        }
    }

    /// When turning **off** `id`, these dependent feature subs are turned off first (same category).
    static func dependents(for category: SidebarCategory, id: String) -> [String] {
        switch category {
        case .ai:
            if id == "Models" { return ["Chats"] }
            return []
        default:
            return []
        }
    }
}
