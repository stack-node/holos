import Foundation
import Combine

enum ServerState {
    case stopped
    case starting
    case running
    case failed(String)
}

@MainActor
final class LlamaServer: ObservableObject {
    static let shared = LlamaServer()

    @Published private(set) var state: ServerState = .stopped
    @Published private(set) var log: [String] = []

    private var process: Process?
    private var logPipe: Pipe?
    private let settings = Settings.shared
    private let maxLogLines = 200

    var statusIcon: String {
        switch state {
        case .stopped:       return "brain"
        case .starting:      return "brain.filled.head.profile"
        case .running:       return "brain.head.profile"
        case .failed:        return "exclamationmark.triangle"
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var endpointURL: URL {
        URL(string: "http://127.0.0.1:\(settings.port)/v1/chat/completions")!
    }

    func start() {
        guard process == nil else { return }
        state = .starting
        appendLog("Starting llama-server…")
        killPortSquatter(settings.port)

        let binaryPath = settings.serverBinaryPath
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            state = .failed("Binary not found: \(binaryPath)")
            appendLog("ERROR: binary not found at \(binaryPath)")
            return
        }

        let modelPath = settings.modelPath
        guard FileManager.default.fileExists(atPath: modelPath) else {
            state = .failed("Model not found: \(modelPath)")
            appendLog("ERROR: model not found at \(modelPath)")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = settings.buildArguments()

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        self.logPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendLog(text.trimmingCharacters(in: .newlines))
                if case .starting = self?.state ?? .stopped {
                    if text.contains("server is listening") || text.contains("HTTP server listening") {
                        self?.state = .running
                    }
                }
            }
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.process = nil
                self?.logPipe?.fileHandleForReading.readabilityHandler = nil
                self?.logPipe = nil
                if proc.terminationStatus != 0 {
                    self?.state = .failed("Exited with code \(proc.terminationStatus)")
                } else {
                    self?.state = .stopped
                }
                self?.appendLog("Process terminated (status \(proc.terminationStatus))")
            }
        }

        do {
            try p.run()
            self.process = p
            appendLog("PID \(p.processIdentifier) — \(binaryPath)")
        } catch {
            state = .failed(error.localizedDescription)
            appendLog("ERROR: \(error.localizedDescription)")
        }
    }

    private func killPortSquatter(_ port: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "lsof -ti:\(port) | xargs kill -9 2>/dev/null; true"]
        try? task.run()
        task.waitUntilExit()
        appendLog("Cleared port \(port).")
    }

    func stop() {
        process?.terminate()
        process = nil
        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe = nil
        state = .stopped
        appendLog("Stopped.")
    }

    func clearLog() {
        log = []
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > maxLogLines {
            log.removeFirst(log.count - maxLogLines)
        }
    }
}
