import Foundation

// MARK: - Manifest

struct ExtensionManifest: Decodable, Identifiable {
    let id: String
    let name: String
    let version: String
    let description: String
    let entry: String
    let provides: [String]
    /// Declarative SwiftUI widget tree (optional; else `widget.json` in the extension folder).
    let widget: ExtensionWidgetSpec?
}

// MARK: - Run state

enum ExtensionRunState: Equatable {
    case stopped, starting, running, failed(String)

    var label: String {
        switch self {
        case .stopped:        return "Stopped"
        case .starting:       return "Starting"
        case .running:        return "Running"
        case .failed(let e):  return "Failed: \(e)"
        }
    }
}

// MARK: - Extension instance

@MainActor
final class HolosExtension: ObservableObject, Identifiable {
    let id: String
    let manifest: ExtensionManifest
    let directory: URL
    /// Resolved from `manifest.widget` or `widget.json` in the extension directory.
    let widgetSpec: ExtensionWidgetSpec?

    @Published private(set) var runState: ExtensionRunState = .stopped {
        didSet {
            // Defer so we never re-enter `ExtensionManager.shared` during its static init
            // (`scan` → `start` → `runState` → this path → `PinManager` → `ExtensionManager.shared`).
            Task { @MainActor in PinManager.shared.refreshWidgetPanels() }
        }
    }
    @Published private(set) var widgetData: [String: String] = [:]

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var audioCapture: AudioCapture?

    init(manifest: ExtensionManifest, directory: URL) {
        self.id         = manifest.id
        self.manifest   = manifest
        self.directory  = directory
        self.widgetSpec  = Self.resolveWidgetSpec(manifest: manifest, directory: directory)
    }

    private static func resolveWidgetSpec(manifest: ExtensionManifest, directory: URL) -> ExtensionWidgetSpec? {
        if let w = manifest.widget { return w }
        let url = directory.appendingPathComponent("widget.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExtensionWidgetSpec.self, from: data)
    }

    var canStart: Bool {
        switch runState { case .stopped, .failed: return true; default: return false }
    }

    func start() {
        guard canStart else { return }
        let entry = directory.appendingPathComponent(manifest.entry)
        guard FileManager.default.fileExists(atPath: entry.path) else {
            runState = .failed("entry not found"); return
        }

        runState = .starting

        let proc   = Process()
        let stdout = Pipe()
        let stdin  = Pipe()

        proc.executableURL       = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments           = ["python3", entry.path]
        proc.currentDirectoryURL = directory
        proc.standardOutput      = stdout
        proc.standardInput       = stdin
        proc.standardError       = Pipe()

        var env = ProcessInfo.processInfo.environment
        let lib = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holos/lib").path
        env["PYTHONPATH"] = env["PYTHONPATH"].map { "\(lib):\($0)" } ?? lib
        proc.environment = env

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .running = self.runState { self.runState = .stopped }
                self.process = nil
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty,
                      let d   = t.data(using: .utf8),
                      let msg = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                else { continue }
                Task { @MainActor [weak self] in self?.handle(message: msg) }
            }
        }

        stdinPipe  = stdin
        stdoutPipe = stdout
        process    = proc

        do {
            try proc.run()
            runState = .running
        } catch {
            runState = .failed(error.localizedDescription)
            return
        }

        startAudioCaptureIfNeeded()
    }

    private func startAudioCaptureIfNeeded() {
        guard manifest.provides.contains("audio") else { return }
        guard ModuleRegistry.shared.isEnabled(.sound) else { return }
        guard audioCapture == nil else { return }
        let capture = AudioCapture(bands: 20)
        capture.onBands = { [weak self] bands, rms in
            self?.sendAudioBands(bands, rms: rms)
        }
        capture.start()
        audioCapture = capture
    }

    /// Stops or starts mic capture for extensions that declare `audio` without restarting the extension process.
    func applySoundModulePreference(_ soundModuleEnabled: Bool) {
        guard manifest.provides.contains("audio") else { return }
        if !soundModuleEnabled {
            audioCapture?.stop()
            audioCapture = nil
            return
        }
        guard case .running = runState else { return }
        startAudioCaptureIfNeeded()
    }

    func stop() {
        audioCapture?.stop()
        audioCapture = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process    = nil
        stdinPipe  = nil
        stdoutPipe = nil
        runState   = .stopped
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.start() }
    }

    func sendCommand(_ action: String) {
        guard let pipe = stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: ["type": "command", "action": action]),
              let line = String(data: data, encoding: .utf8)
        else { return }
        pipe.fileHandleForWriting.write((line + "\n").data(using: .utf8)!)
    }

    private func sendAudioBands(_ bands: [Double], rms: Double) {
        guard let pipe = stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: ["type": "audio_bands", "bands": bands, "rms": rms]),
              let line = String(data: data, encoding: .utf8)
        else { return }
        pipe.fileHandleForWriting.write((line + "\n").data(using: .utf8)!)
    }

    private func handle(message msg: [String: Any]) {
        guard msg["type"] as? String == "widget_update",
              let raw = msg["data"] as? [String: Any] else { return }
        widgetData = raw.reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
    }
}

// MARK: - Extension manager

@MainActor
final class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()
    private init() {
        loadAutoStart()
        bootstrap(); scan()
    }

    @Published private(set) var extensions: [HolosExtension] = []
    /// Extension IDs that should launch automatically when Holos starts (and after a rescan).
    @Published private(set) var autoStartExtensionIDs: Set<String> = []

    private var extensionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holos/extensions")
            .resolvingSymlinksInPath()
    }

    private var autoStartFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holos/configuration/extension_autostart.json")
    }

    func isAutoStart(_ extensionID: String) -> Bool {
        autoStartExtensionIDs.contains(extensionID)
    }

    func setAutoStart(_ extensionID: String, _ enabled: Bool) {
        var next = autoStartExtensionIDs
        if enabled { next.insert(extensionID) } else { next.remove(extensionID) }
        autoStartExtensionIDs = next
        saveAutoStart()
        if enabled, let ext = extensions.first(where: { $0.id == extensionID }), ext.canStart {
            ext.start()
        }
    }

    private func loadAutoStart() {
        guard let data = try? Data(contentsOf: autoStartFileURL),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        autoStartExtensionIDs = Set(ids)
    }

    private func saveAutoStart() {
        try? FileManager.default.createDirectory(
            at: autoStartFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sorted = autoStartExtensionIDs.sorted()
        try? JSONEncoder().encode(sorted).write(to: autoStartFileURL)
    }

    private func startAutoStartExtensions() {
        for ext in extensions where autoStartExtensionIDs.contains(ext.id) && ext.canStart {
            ext.start()
        }
    }

    func scan() {
        let dir = extensionsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        extensions = items.compactMap { url in
            guard let data     = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data)
            else { return nil }
            return HolosExtension(manifest: manifest, directory: url)
        }.sorted { $0.manifest.name < $1.manifest.name }
        startAutoStartExtensions()
        syncSoundModuleWithRegistry()
    }

    func syncSoundModuleWithRegistry() {
        let on = ModuleRegistry.shared.isEnabled(.sound)
        for ext in extensions {
            ext.applySoundModulePreference(on)
        }
    }

    // MARK: Bootstrap

    private func bootstrap() {
        writeLib()
    }

    private func writeLib() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/holos/lib/holos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("__init__.py")
        // Always overwrite so extensions get the latest API on each launch.
        try? holosPyLib.write(to: url, atomically: true, encoding: .utf8)
    }

}

// MARK: - Embedded Python sources

private let holosPyLib = #"""
import sys
import json
import threading


class AudioBands:
    """Spectrum frame delivered by the host at ~30 fps when audio capture is active."""
    __slots__ = ("bands", "rms")

    def __init__(self, bands: list, rms: float):
        self.bands = bands  # list[float] in [0, 1], one value per frequency band
        self.rms = rms      # overall loudness in [0, 1]


class Widget:
    def __init__(self, widget_id):
        self.widget_id = widget_id

    def update(self, data: dict):
        _send({"type": "widget_update", "widget_id": self.widget_id, "data": data})


class Extension:
    def __init__(self):
        self._handlers = {}
        self._audio_handler = None

    def on_command(self, action):
        def decorator(fn):
            self._handlers[action] = fn
            return fn
        return decorator

    def on_audio_bands(self, fn):
        """Decorator — register callback for real-time audio spectrum data.

        fn(audio: AudioBands) is called at ~30 fps while the host captures audio.
        Requires "audio" in the extension manifest's ``provides`` list.
        """
        self._audio_handler = fn
        return fn

    def run(self):
        def _listen():
            for line in sys.stdin:
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                    t = msg.get("type")
                    if t == "command":
                        h = self._handlers.get(msg.get("action", ""))
                        if h:
                            h(msg)
                    elif t == "audio_bands":
                        h = self._audio_handler
                        if h:
                            h(AudioBands(msg.get("bands", []), msg.get("rms", 0.0)))
                except Exception:
                    pass
        threading.Thread(target=_listen, daemon=True).start()


def _send(msg: dict):
    print(json.dumps(msg, ensure_ascii=False), flush=True)
"""#

