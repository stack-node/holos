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
            case extensionBuilder(ExtensionBuilderBody)
        }

        struct CodeBody: Codable {
            var code: String
            var languageKey: String
            var openFilePath: String?
        }

        struct TextBody: Codable {
            var text: String
            var openFilePath: String?
        }

        struct TerminalBody: Codable {
            var lines: [String]
        }

        struct ExtensionBuilderBody: Codable {
            var selectedExtensionID: String?
            var editorMode: String
            var entrySource: String
            var manifestSource: String?
            var widgetSource: String?
            var activeRelatedFile: String?
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
    @Published var openFile: URL? = nil

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            self.text = content
            self.openFile = url
            DevelopmentSessionStore.shared.sessionLabelsDidChange()
        }
    }

    func save() {
        guard let url = openFile else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        if let url = openFile {
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        }
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            try? self.text.write(to: url, atomically: true, encoding: .utf8)
            self.openFile = url
            DevelopmentSessionStore.shared.sessionLabelsDidChange()
        }
    }
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

// MARK: - Extension Builder session

enum ExtensionBuilderEditorMode: String, CaseIterable {
    case visual
    case code
}

/// Which file the builder is editing (`entry` = manifest’s Python entry; use sidebar parent row).
enum ExtensionBuilderActiveFile: String, CaseIterable, Hashable {
    case entry
    case manifest
    case widget
}

enum ExtensionBuilderSidebarFile: Hashable, Identifiable {
    case manifest
    case widget

    var id: String {
        switch self {
        case .manifest: return "manifest"
        case .widget: return "widget"
        }
    }

    /// Extra rows under a session: manifest always; `widget.json` when present on disk.
    static func childRows(for ext: HolosExtension) -> [ExtensionBuilderSidebarFile] {
        var rows: [ExtensionBuilderSidebarFile] = [.manifest]
        let w = ext.directory.appendingPathComponent("widget.json")
        if FileManager.default.fileExists(atPath: w.path) {
            rows.append(.widget)
        }
        return rows
    }

    func label(for ext: HolosExtension) -> String {
        switch self {
        case .manifest: return "manifest.json"
        case .widget: return "widget.json"
        }
    }
}

@MainActor
final class ExtensionBuilderSession: ObservableObject {
    @Published var selectedExtensionID: String?
    @Published var editorMode: ExtensionBuilderEditorMode = .code
    @Published var activeFile: ExtensionBuilderActiveFile = .entry
    @Published var entrySource: String = ""
    @Published var manifestSource: String = ""
    @Published var widgetSource: String = ""

    func applySelectedExtensionID(_ id: String?) {
        selectedExtensionID = id
        activeFile = .entry
        guard let id,
              let ext = ExtensionManager.shared.extensions.first(where: { $0.id == id })
        else {
            entrySource = ""
            manifestSource = ""
            widgetSource = ""
            return
        }
        reloadAllSourcesFromDisk(for: ext)
        DevelopmentSessionStore.shared.sessionLabelsDidChange()
    }

    func focusActiveFile(_ file: ExtensionBuilderActiveFile) {
        activeFile = file
    }

    private func reloadAllSourcesFromDisk(for ext: HolosExtension) {
        let manifestURL = ext.directory.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifestURL.path),
           let t = try? String(contentsOf: manifestURL, encoding: .utf8) {
            manifestSource = t
        } else {
            manifestSource = ""
        }

        let entryURL = ext.directory.appendingPathComponent(ext.manifest.entry)
        if FileManager.default.fileExists(atPath: entryURL.path),
           let t = try? String(contentsOf: entryURL, encoding: .utf8) {
            entrySource = t
        } else {
            entrySource = ""
        }

        let widgetURL = ext.directory.appendingPathComponent("widget.json")
        if FileManager.default.fileExists(atPath: widgetURL.path),
           let t = try? String(contentsOf: widgetURL, encoding: .utf8) {
            widgetSource = t
        } else {
            widgetSource = ""
        }
    }

    func save() {
        guard let id = selectedExtensionID,
              let ext = ExtensionManager.shared.extensions.first(where: { $0.id == id })
        else { return }

        let root = ext.directory
        let url: URL
        switch activeFile {
        case .entry:
            url = root.appendingPathComponent(ext.manifest.entry)
        case .manifest:
            url = root.appendingPathComponent("manifest.json")
        case .widget:
            url = root.appendingPathComponent("widget.json")
        }

        let text: String
        switch activeFile {
        case .entry: text = entrySource
        case .manifest: text = manifestSource
        case .widget: text = widgetSource
        }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? text.write(to: url, atomically: true, encoding: .utf8)
        ExtensionManager.shared.scan()
        if let refreshed = ExtensionManager.shared.extensions.first(where: { $0.id == id }) {
            reloadAllSourcesFromDisk(for: refreshed)
        }
        DevelopmentSessionStore.shared.sessionLabelsDidChange()
    }
}

// MARK: - Tool payload

enum DevelopmentToolSession {
    case code(CodeEditorSession)
    case text(TextEditorSession)
    case terminal(TerminalSession)
    case extensionBuilder(ExtensionBuilderSession)
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
        switch instance.tool {
        case .code(let m):
            return Self.sidebarTitle(
                fileURL: m.openFile,
                untitledAmongPeers: peers.filter {
                    if case .code(let cm) = $0.tool { return cm.openFile == nil }
                    return false
                },
                instanceId: instance.id,
                duplicatePeersMatchingURL: peers.filter {
                    guard let u = m.openFile else { return false }
                    if case .code(let cm) = $0.tool, let ou = cm.openFile {
                        return ou.standardizedFileURL == u.standardizedFileURL
                    }
                    return false
                }
            )
        case .text(let m):
            return Self.sidebarTitle(
                fileURL: m.openFile,
                untitledAmongPeers: peers.filter {
                    if case .text(let tm) = $0.tool { return tm.openFile == nil }
                    return false
                },
                instanceId: instance.id,
                duplicatePeersMatchingURL: peers.filter {
                    guard let u = m.openFile else { return false }
                    if case .text(let tm) = $0.tool, let ou = tm.openFile {
                        return ou.standardizedFileURL == u.standardizedFileURL
                    }
                    return false
                }
            )
        case .terminal:
            return "Shell \(idx)"
        case .extensionBuilder(let m):
            return Self.extensionBuilderSidebarTitle(
                m: m,
                peers: peers,
                instanceId: instance.id
            )
        }
    }

    private static func extensionBuilderSidebarTitle(
        m: ExtensionBuilderSession,
        peers: [DevelopmentInstance],
        instanceId: UUID
    ) -> String {
        let builderPeers = peers.compactMap { inst -> (UUID, ExtensionBuilderSession)? in
            if case .extensionBuilder(let s) = inst.tool { return (inst.id, s) }
            return nil
        }
        guard let extID = m.selectedExtensionID,
              let holosExt = ExtensionManager.shared.extensions.first(where: { $0.id == extID })
        else {
            let untitledPeers = builderPeers.filter { $0.1.selectedExtensionID == nil }
            guard untitledPeers.count > 1 else { return "Untitled" }
            let ord = (untitledPeers.firstIndex { $0.0 == instanceId } ?? 0) + 1
            return "Untitled \(ord)"
        }

        let name = holosExt.manifest.name
        let sameSelection = builderPeers.filter { $0.1.selectedExtensionID == extID }
        if sameSelection.count > 1 {
            let ord = (sameSelection.firstIndex { $0.0 == instanceId } ?? 0) + 1
            return Self.truncateSidebarLabel("\(name) (\(ord))")
        }
        return Self.truncateSidebarLabel(name)
    }

    /// Call when a session’s displayed file name may change (open/save as); avoids refreshing the sidebar on every keystroke.
    func sessionLabelsDidChange() {
        objectWillChange.send()
    }

    private static func sidebarTitle(
        fileURL: URL?,
        untitledAmongPeers: [DevelopmentInstance],
        instanceId: UUID,
        duplicatePeersMatchingURL: [DevelopmentInstance]
    ) -> String {
        guard let url = fileURL else {
            let n = untitledAmongPeers.count
            guard n > 1 else { return "Untitled" }
            let ord = (untitledAmongPeers.firstIndex { $0.id == instanceId } ?? 0) + 1
            return "Untitled \(ord)"
        }

        let name = url.lastPathComponent
        if duplicatePeersMatchingURL.count > 1 {
            let ord = (duplicatePeersMatchingURL.firstIndex { $0.id == instanceId } ?? 0) + 1
            return Self.truncateSidebarLabel("\(name) (\(ord))")
        }
        return Self.truncateSidebarLabel(name)
    }

    /// Shortens very long file names so sidebar rows stay readable.
    private static func truncateSidebarLabel(_ s: String, maxLength: Int = 30) -> String {
        guard s.count > maxLength else { return s }
        let head = 12
        let tail = 10
        let start = String(s.prefix(head))
        let end = String(s.suffix(tail))
        return "\(start)…\(end)"
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

    /// Selects an Extension Builder session and which file row is active (entry = session parent row).
    func selectExtensionBuilder(_ instanceId: UUID, activeFile: ExtensionBuilderActiveFile) {
        guard instance(for: instanceId) != nil else { return }
        stopAllCodeWatching()
        selectedInstanceId = instanceId
        if let inst = instance(for: instanceId),
           case .extensionBuilder(let m) = inst.tool {
            m.focusActiveFile(activeFile)
        }
        syncCodeFileWatching()
    }

    func isExtensionBuilderFileActive(_ instanceId: UUID, _ activeFile: ExtensionBuilderActiveFile) -> Bool {
        guard selectedInstanceId == instanceId,
              let inst = instance(for: instanceId),
              case .extensionBuilder(let m) = inst.tool else { return false }
        return m.activeFile == activeFile
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
        case .extensionBuilder:
            tool = .extensionBuilder(ExtensionBuilderSession())
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
        case .extensionBuilder(let m):
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
                let body = DevelopmentWorkspacePersistence.InstanceSnapshot.TextBody(
                    text: m.text,
                    openFilePath: m.openFile?.path
                )
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
            case .extensionBuilder(let m):
                let body = DevelopmentWorkspacePersistence.InstanceSnapshot.ExtensionBuilderBody(
                    selectedExtensionID: m.selectedExtensionID,
                    editorMode: m.editorMode.rawValue,
                    entrySource: m.entrySource,
                    manifestSource: m.manifestSource,
                    widgetSource: m.widgetSource,
                    activeRelatedFile: m.activeFile.rawValue
                )
                snaps.append(DevelopmentWorkspacePersistence.InstanceSnapshot(
                    id: inst.id,
                    context: inst.context.rawValue,
                    payload: .extensionBuilder(body)
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
                if let p = body.openFilePath {
                    m.openFile = URL(fileURLWithPath: p)
                }
                restored.append(DevelopmentInstance(id: snap.id, context: ctx, tool: .text(m)))
            case .terminal(let body):
                let m = TerminalSession()
                m.lines = body.lines.isEmpty ? terminalDefaultLines : body.lines
                restored.append(DevelopmentInstance(id: snap.id, context: ctx, tool: .terminal(m)))
            case .extensionBuilder(let body):
                let m = ExtensionBuilderSession()
                m.selectedExtensionID = body.selectedExtensionID
                m.editorMode = ExtensionBuilderEditorMode(rawValue: body.editorMode) ?? .code
                m.entrySource = body.entrySource
                m.manifestSource = body.manifestSource ?? ""
                m.widgetSource = body.widgetSource ?? ""
                m.activeFile = ExtensionBuilderActiveFile(rawValue: body.activeRelatedFile ?? "") ?? .entry
                restored.append(DevelopmentInstance(id: snap.id, context: ctx, tool: .extensionBuilder(m)))
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
