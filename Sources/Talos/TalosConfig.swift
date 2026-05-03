import Foundation
import Combine
import AppKit

enum GlowStyle: String, CaseIterable, Codable {
    case off         = "off"
    case solidColor  = "solidColor"
    case mimicBorder = "mimicBorder"

    var label: String {
        switch self {
        case .off:         return "Off"
        case .solidColor:  return "Solid Color"
        case .mimicBorder: return "Mimic Border"
        }
    }
}

final class TalosConfig: ObservableObject {
    static let shared = TalosConfig()

    @Published var backgroundOpacity: Double = 0.18       { didSet { save() } }
    @Published var blurEnabled: Bool         = true       { didSet { save() } }
    @Published var blurStrength: Double      = 0.3        { didSet { save() } }
    @Published var glowStyle: GlowStyle      = .mimicBorder { didSet { save() } }
    @Published var glowIntensity: Double     = 1.0        { didSet { save() } }
    @Published var glowSize: Double          = 10.0       { didSet { save() } }
    @Published var glowBlur: Double          = 7.0        { didSet { save() } }
    @Published var glowColorR: Double        = 0.55       { didSet { save() } }
    @Published var glowColorG: Double        = 0.25       { didSet { save() } }
    @Published var glowColorB: Double        = 0.95       { didSet { save() } }

    private let fileURL: URL

    private struct Stored: Codable {
        var backgroundOpacity: Double
        var blurEnabled: Bool
        var blurStrength: Double
        var glowStyle: GlowStyle
        var glowIntensity: Double
        var glowSize: Double
        var glowBlur: Double
        var glowColorR: Double
        var glowColorG: Double
        var glowColorB: Double
    }

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/stacknode/talos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            backgroundOpacity = stored.backgroundOpacity
            blurEnabled       = stored.blurEnabled
            blurStrength      = stored.blurStrength
            glowStyle         = stored.glowStyle
            glowIntensity     = stored.glowIntensity
            glowSize          = stored.glowSize
            glowBlur          = stored.glowBlur
            glowColorR        = stored.glowColorR
            glowColorG        = stored.glowColorG
            glowColorB        = stored.glowColorB
        }
    }

    var blurMaterial: NSVisualEffectView.Material {
        switch blurStrength {
        case ..<0.25: return .menu
        case ..<0.5:  return .popover
        case ..<0.75: return .hudWindow
        default:      return .fullScreenUI
        }
    }

    private func save() {
        let stored = Stored(
            backgroundOpacity: backgroundOpacity,
            blurEnabled: blurEnabled,
            blurStrength: blurStrength,
            glowStyle: glowStyle,
            glowIntensity: glowIntensity,
            glowSize: glowSize,
            glowBlur: glowBlur,
            glowColorR: glowColorR,
            glowColorG: glowColorG,
            glowColorB: glowColorB
        )
        try? JSONEncoder().encode(stored).write(to: fileURL)
    }
}
