import AppKit
import Combine
import Darwin

@MainActor
final class CodeEditorSession: ObservableObject {

    @Published var code: String = ""
    @Published var language: CodeLanguage = .swift
    @Published var openFile: URL? = nil

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1

    // MARK: - File ops

    func open(_ item: FileItem) {
        guard let content = try? String(contentsOf: item.url, encoding: .utf8) else { return }
        code = content
        language = item.detectedLanguage()
        openFile = item.url
        if RightSidebarState.shared.autoReload { startWatching() }
    }

    func save() {
        guard let url = openFile else { return }
        try? code.write(to: url, atomically: true, encoding: .utf8)
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
            try? self.code.write(to: url, atomically: true, encoding: .utf8)
            self.openFile = url
            self.language = FileItem(url: url, isDirectory: false, depth: 0).detectedLanguage()
        }
    }

    func reload() {
        guard let url = openFile,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        code = content
    }

    // MARK: - File watcher

    func startWatching() {
        stopWatching()
        guard let url = openFile else { return }
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchedFD, fd >= 0 { close(fd) }
            self?.watchedFD = -1
        }
        source.resume()
        fileWatcher = source
    }

    func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }
}
