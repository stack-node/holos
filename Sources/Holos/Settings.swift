import Foundation

final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var serverBinaryPath: String { didSet { save() } }
    @Published var modelPath: String        { didSet { save() } }
    @Published var port: Int                { didSet { save() } }
    @Published var contextSize: Int         { didSet { save() } }
    @Published var gpuLayers: Int           { didSet { save() } }

    private let fileURL: URL

    private struct Stored: Codable {
        var serverBinaryPath: String
        var modelPath: String
        var port: Int
        var contextSize: Int
        var gpuLayers: Int
    }

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holos/configuration")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            serverBinaryPath = stored.serverBinaryPath
            modelPath        = stored.modelPath
            port             = stored.port
            contextSize      = stored.contextSize
            gpuLayers        = stored.gpuLayers
        } else {
            serverBinaryPath = Self.detectLlamaServer()
            modelPath        = NSHomeDirectory() + "/.config/holos/models/model.gguf"
            port             = 8080
            contextSize      = 8192
            gpuLayers        = 99
        }
    }

    private static func detectLlamaServer() -> String {
        let candidates = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server",
            NSHomeDirectory() + "/.local/bin/llama-server",
            NSHomeDirectory() + "/llama.cpp/build/bin/llama-server",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    private func save() {
        let stored = Stored(
            serverBinaryPath: serverBinaryPath,
            modelPath: modelPath,
            port: port,
            contextSize: contextSize,
            gpuLayers: gpuLayers
        )
        try? JSONEncoder().encode(stored).write(to: fileURL)
    }

    func buildArguments() -> [String] {
        [
            "--model", modelPath,
            "--port", "\(port)",
            "--ctx-size", "\(contextSize)",
            "--n-gpu-layers", "\(gpuLayers)",
            "--flash-attn", "on",
        ]
    }
}
