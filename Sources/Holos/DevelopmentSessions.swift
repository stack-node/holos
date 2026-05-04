import AppKit
import Combine
import Foundation

// MARK: - Persisted snapshot (Application Support JSON)

private enum DevelopmentWorkspacePersistence {
    static let fileName = "development_workspace.json"
    static let bootstrapKey = "holos.development.workspaceBootstrapped"

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Holos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    struct WorkspaceFile: Codable {
        var version: Int
        var instances: [InstanceSnapshot]
        var selectedInstanceId: UUID?
    }

    struct InstanceSnapshot: Codable {
        var id: UUID
        var context: String
        var payload: Payload

        enum Payload: Codable {
            case code(CodeBody)
            case text(TextBody)
            case terminal(TerminalBody)
        }

        struct CodeBody: Codable {
            var code: String
            var languageKey: String
            var openFilePath: String?
        }

        struct TextBody: Codable {
            var text: String
        }

        struct TerminalBody: Codable {
            var lines: [String]
        }
    }

    static func load() -> WorkspaceFile? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(WorkspaceFile.self, from: data)
    }

    static func save(_ workspace: WorkspaceFile) {
        let url = fileURL
        guard let data = try? JSONEncoder().encode(workspace) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

// MARK: - Text editor session

@MainActor
final class TextEditorSession: ObservableObject {
    @Published var text = ""
}

// MARK: - Terminal session

private let terminalDefaultLines: [String] = [
    "Holos terminal — no shell session yet.",
    "Lines echo locally; type `clear` to reset the buffer.",
    "",
]

@MainActor
final class TerminalSession: ObservableObject {
    @Published var lines: [String] = terminalDefaultLines
    @Published var input = ""

    func commitInput() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        guard !t.isEmpty else { return }
        if t == "clear" {
            lines = [
                "Buffer cleared.",
                "",
            ]
            return
        }
        lines.append("% \(t)")
        lines.append(t)
        lines.append("")
    }
}

// MARK: - Tool payload

enum DevelopmentToolSession {
    case code(CodeEditorSession)
    case text(TextEditorSession)
    case terminal(TerminalSession)
}

struct DevelopmentInstance: Identifiable {
    let id: UUID
    let context: RightContext
    let tool: DevelopmentToolSession
}

// MARK: - Store

@MainActor
final class DevelopmentSessionStore: ObservableObject {
    static let shared = DevelopmentSessionStore()

    @Published private(set) var instances: [DevelopmentInstance] = []
    @Published var selectedInstanceId: UUID?

    private var persistenceSubs: [UUID: AnyCancellable] = [:]
    private var persistWorkItem: DispatchWorkItem?
    private var isRestoring = false

    private init() {
        loadFromDiskIfNeeded()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistImmediately()
            }
        }
    }

    func instance(for id: UUID) -> DevelopmentInstance? {
        instances.first { $0.id == id }
    }

    func instances(for context: RightContext) -> [DevelopmentInstance] {
        instances.filter { $0.context == context }
    }

    func displayTitle(for instance: DevelopmentInstance) -> String {
        let peers = instances(for: instance.context)
        let idx = (peers.firstIndex { $0.id == instance.id } ?? 0) + 1
        switch instance.context {
        case .codeEditor: return "Code \(idx)"
        case .textEditor: return "Text \(idx)"
        case .terminal:   return "Shell \(idx)"
        }
    }

    /// Ensures selection matches the current utilities tab; does not remove instances.
    func ensureSelectionForCurrentTab(category: SidebarCategory, tab: String) {
        guard category == .development, let ctx = RightContext(rawValue: tab) else { return }
        let list = instances(for: ctx)
        if list.isEmpty {
            if instances.isEmpty, !UserDefaults.standard.bool(forKey: DevelopmentWorkspacePersistence.bootstrapKey) {
                UserDefaults.standard.set(true, forKey: DevelopmentWorkspacePersistence.bootstrapKey)
                selectedInstanceId = insertSession(for: ctx)
                syncCodeFileWatching()
                return
            }
            selectedInstanceId = nil
            return
        }
        if let sid = selectedInstanceId,
           let inst = instance(for: sid), inst.context == ctx {
            syncCodeFileWatching()
            return
        }
        selectedInstanceId = list.last?.id
        syncCodeFileWatching()
    }

    func activateTool(_ context: RightContext) {
        let list = instances(for: context)
        if list.isEmpty {
            selectedInstanceId = insertSession(for: context)
            syncCodeFileWatching()
            return
        }
        if let sid = selectedInstanceId,
           let inst = instance(for: sid), inst.context == context {
            syncCodeFileWatching()
            return
        }
        selectedInstanceId = list.last?.id
        syncCodeFileWatching()
    }

    func selectInstance(_ id: UUID) {
        guard instance(for: id) != nil else { return }
        stopAllCodeWatching()
        selectedInstanceId = id
        syncCodeFileWatching()
    }

    func addSession(for context: RightContext) {
        NavigationState.shared.globalTab = nil
        NavigationState.shared.selectedTab = context.rawValue
        RightSidebarState.shared.context = context
        stopAllCodeWatching()
        selectedInstanceId = insertSession(for: context)
        syncCodeFileWatching()
    }

    /// Removes a session and updates selection; persists immediately.
    func removeSession(_ id: UUID) {
        guard let idx = instances.firstIndex(where: { $0.id == id }) else { return }
        let removed = instances[idx]
        if case .code(let m) = removed.tool { m.stopWatching() }
        persistenceSubs[id]?.cancel()
        persistenceSubs[id] = nil
        instances.remove(at: idx)

        if selectedInstanceId == id {
            let peers = instances.filter { $0.context == removed.context }
            if let next = peers.last {
                selectedInstanceId = next.id
            } else if let any = instances.last {
                selectedInstanceId = any.id
                NavigationState.shared.globalTab = nil
                NavigationState.shared.selectedTab = any.context.rawValue
                RightSidebarState.shared.context = any.context
            } else {
                selectedInstanceId = nil
            }
        }
        syncCodeFileWatching()
        persistImmediately()
    }

    func applyAutoReloadSetting() {
        syncCodeFileWatching()
    }

    @discardableResult
    private func insertSession(for context: RightContext, id: UUID? = nil) -> UUID {
        let uid = id ?? UUID()
        let tool: DevelopmentToolSession
        switch context {
        case .codeEditor:
            tool = .code(CodeEditorSession())
        case .textEditor:
            tool = .text(TextEditorSession())
        case .terminal:
            tool = .terminal(TerminalSession())
        }
        instances.append(DevelopmentInstance(id: uid, context: context, tool: tool))
        registerPersistenceHooks(id: uid, tool: tool)
        schedulePersist()
        return uid
    }

    private func stopAllCodeWatching() {
        for inst in instances {
            if case .code(let m) = inst.tool { m.stopWatching() }
        }
    }

    private func syncCodeFileWatching() {
        stopAllCodeWatching()
        guard RightSidebarState.shared.autoReload,
              let id = selectedInstanceId,
              let inst = instance(for: id),
              case .code(let model) = inst.tool,
              model.openFile != nil
        else { return }
        model.startWatching()
    }

    // MARK: - Persistence

    private func registerPersistenceHooks(id: UUID, tool: DevelopmentToolSession) {
        persistenceSubs[id]?.cancel()
        switch tool {
        case .code(let m):
            persistenceSubs[id] = m.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.schedulePersist() }
        case .text(let m):
            persistenceSubs[id] = m.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.schedulePersist() }
        case .terminal(let m):
            persistenceSubs[id] = m.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.schedulePersist() }
        }
    }

    private func schedulePersist() {
        guard !isRestoring else { return }
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.persistImmediately()
        }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    func persistImmediately() {
        persistWorkItem?.cancel()
        persistWorkItem = nil
        guard !isRestoring else { return }

        var snaps: [DevelopmentWorkspacePersistence.InstanceSnapshot] = []
        snaps.reserveCapacity(instances.count)

        for inst in instances {
            switch inst.tool {
            case .code(let m):
                let body = DevelopmentWorkspacePersistence.InstanceSnapshot.CodeBody(
                    code: m.code,
                    languageKey: m.language.persistenceKey,
                    openFilePath: m.openFile?.path
                )
                snaps.append(DevelopmentWorkspacePersistence.InstanceSnapshot(
                    id: inst.id,
                    context: inst.context.rawValue,
                    payload: .code(body)
                ))
            case .text(let m):
                let body = DevelopmentWorkspacePersistence.InstanceSnapshot.TextBody(text: m.text)
                snaps.append(DevelopmentWorkspacePersistence.InstanceSnapshot(
                    id: inst.id,
                    context: inst.context.rawValue,
                    payload: .text(body)
                ))
            case .terminal(let m):
                let capped = Array(m.lines.suffix(500))
                let body = DevelopmentWorkspacePersistence.InstanceSnapshot.TerminalBody(lines: capped)
                snaps.append(DevelopmentWorkspacePersistence.InstanceSnapshot(
                    id: inst.id,
                    context: inst.context.rawValue,
                    payload: .terminal(body)
                ))
            }
        }

        let file = DevelopmentWorkspacePersistence.WorkspaceFile(
            version: 1,
            instances: snaps,
            selectedInstanceId: selectedInstanceId
        )
        DevelopmentWorkspacePersistence.save(file)
    }

    private func loadFromDiskIfNeeded() {
        guard let file = DevelopmentWorkspacePersistence.load() else { return }
        isRestoring = true
        defer { isRestoring = false }

        var restored: [DevelopmentInstance] = []
        restored.reserveCapacity(file.instances.count)

        for snap in file.instances {
            guard let ctx = RightContext(rawValue: snap.context) else { continue }
            switch snap.payload {
            case .code(let body):
                let m = CodeEditorSession()
                m.code = body.code
                m.language = CodeLanguage(persistenceKey: body.languageKey) ?? .plainText
                if let p = body.openFilePath {
                    m.openFile = URL(fileURLWithPath: p)
                }
                let inst = DevelopmentInstance(id: snap.id, context: ctx, tool: .code(m))
                restored.append(inst)
            case .text(let body):
                let m = TextEditorSession()
                m.text = body.text
                restored.append(DevelopmentInstance(id: snap.id, context: ctx, tool: .text(m)))
            case .terminal(let body):
                let m = TerminalSession()
                m.lines = body.lines.isEmpty ? terminalDefaultLines : body.lines
                restored.append(DevelopmentInstance(id: snap.id, context: ctx, tool: .terminal(m)))
            }
        }

        instances = restored
        for inst in instances {
            registerPersistenceHooks(id: inst.id, tool: inst.tool)
        }

        if let sid = file.selectedInstanceId, instance(for: sid) != nil {
            selectedInstanceId = sid
        } else {
            selectedInstanceId = instances.last?.id
        }

        UserDefaults.standard.set(true, forKey: DevelopmentWorkspacePersistence.bootstrapKey)
        syncCodeFileWatching()
    }
}
