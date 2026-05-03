import Foundation

final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var serverBinaryPath: String {
        didSet { UserDefaults.standard.set(serverBinaryPath, forKey: "serverBinaryPath") }
    }
    @Published var modelPath: String {
        didSet { UserDefaults.standard.set(modelPath, forKey: "modelPath") }
    }
    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "port") }
    }
    @Published var contextSize: Int {
        didSet { UserDefaults.standard.set(contextSize, forKey: "contextSize") }
    }
    @Published var gpuLayers: Int {
        didSet { UserDefaults.standard.set(gpuLayers, forKey: "gpuLayers") }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.serverBinaryPath = defaults.string(forKey: "serverBinaryPath")
            ?? Self.detectLlamaServer()
        self.modelPath = defaults.string(forKey: "modelPath")
            ?? (NSHomeDirectory() + "/.config/StackNode/Models/qwen2.5-coder-7b-instruct-q5_k_m.gguf")
        self.port = defaults.integer(forKey: "port").nonZero ?? 8080
        self.contextSize = defaults.integer(forKey: "contextSize").nonZero ?? 8192
        self.gpuLayers = defaults.integer(forKey: "gpuLayers") == 0
            ? (defaults.object(forKey: "gpuLayers") == nil ? 99 : 0)
            : defaults.integer(forKey: "gpuLayers")
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

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
