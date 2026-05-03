import Foundation
import Combine
import AppKit

final class TalosConfig: ObservableObject {
    static let shared = TalosConfig()

    @Published var backgroundOpacity: Double = 0.18  { didSet { save() } }
    @Published var blurEnabled: Bool         = true  { didSet { save() } }
    @Published var blurStrength: Double      = 0.3   { didSet { save() } }
    @Published var glowEnabled: Bool         = true  { didSet { save() } }
    @Published var glowIntensity: Double     = 1.0   { didSet { save() } }
    @Published var glowSize: Double          = 10.0  { didSet { save() } }
    @Published var glowBlur: Double          = 7.0   { didSet { save() } }

    private let fileURL: URL

    private struct Stored: Codable {
        var backgroundOpacity: Double
        var blurEnabled: Bool
        var blurStrength: Double
        var glowEnabled: Bool
        var glowIntensity: Double
        var glowSize: Double
        var glowBlur: Double
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
            glowEnabled       = stored.glowEnabled
            glowIntensity     = stored.glowIntensity
            glowSize          = stored.glowSize
            glowBlur          = stored.glowBlur
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
            glowEnabled: glowEnabled,
            glowIntensity: glowIntensity,
            glowSize: glowSize,
            glowBlur: glowBlur
        )
        try? JSONEncoder().encode(stored).write(to: fileURL)
    }
}
