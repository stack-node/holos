import SwiftUI
import AppKit

// MARK: - Model

struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let depth: Int
    var id: URL { url }

    var name: String { url.lastPathComponent }

    var icon: String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "swift":                          return "swift"
        case "py":                             return "play.fill"
        case "js", "ts", "jsx", "tsx", "mjs": return "curlybraces"
        case "json":                           return "curlybraces.square"
        case "md", "txt", "rst":              return "doc.text"
        case "html", "htm", "xml":            return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "less":           return "paintbrush"
        case "sh", "zsh", "bash":             return "terminal"
        case "png", "jpg", "jpeg", "gif",
             "webp", "svg", "ico":            return "photo"
        case "pdf":                            return "doc.richtext"
        default:                               return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return Color(red: 0.55, green: 0.75, blue: 1.0) }
        switch url.pathExtension.lowercased() {
        case "swift":                          return Color(red: 1.0, green: 0.55, blue: 0.3)
        case "py":                             return Color(red: 0.6, green: 0.85, blue: 0.4)
        case "js", "ts", "jsx", "tsx":        return Color(red: 1.0, green: 0.85, blue: 0.3)
        case "json":                           return Color(red: 0.7, green: 0.7, blue: 0.7)
        case "md", "txt":                      return Color(white: 0.6)
        case "css", "scss":                    return Color(red: 0.4, green: 0.7, blue: 1.0)
        case "html", "htm":                    return Color(red: 1.0, green: 0.5, blue: 0.3)
        case "sh", "zsh", "bash":             return Color(red: 0.5, green: 1.0, blue: 0.7)
        default:                               return Color(white: 0.55)
        }
    }

    func detectedLanguage() -> CodeLanguage {
        switch url.pathExtension.lowercased() {
        case "swift":                          return .swift
        case "py":                             return .python
        case "js", "ts", "jsx", "tsx", "mjs": return .javascript
        default:                               return .plainText
        }
    }

    static func children(of url: URL, depth: Int) -> [FileItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: []
        ) else { return [] }

        return entries
            .filter { u in
                let hidden = (try? u.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
                return !hidden && u.lastPathComponent != ".DS_Store"
            }
            .map { u in
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileItem(url: u, isDirectory: isDir, depth: depth)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

// MARK: - Persistent state

@MainActor
final class FileExplorerState: ObservableObject {
    static let shared = FileExplorerState()
    private init() { rebuild() }

    private let root = URL(fileURLWithPath: NSHomeDirectory())
    @Published var visibleItems: [FileItem] = []
    @Published var expanded: Set<URL> = []

    func toggle(_ item: FileItem) {
        if expanded.contains(item.url) {
            // Collapse: remove this dir and all descendants
            expanded.remove(item.url)
            expanded = expanded.filter { !$0.path.hasPrefix(item.url.path + "/") }
        } else {
            expanded.insert(item.url)
        }
        rebuild()
    }

    private func rebuild() {
        var result: [FileItem] = []
        append(children: FileItem.children(of: root, depth: 0), into: &result)
        visibleItems = result
    }

    private func append(children: [FileItem], into result: inout [FileItem]) {
        for item in children {
            result.append(item)
            if item.isDirectory && expanded.contains(item.url) {
                append(children: FileItem.children(of: item.url, depth: item.depth + 1), into: &result)
            }
        }
    }
}

// MARK: - View

struct FileExplorerView: View {
    let onSelect: (FileItem) -> Void
    var selectedURL: URL?

    @ObservedObject private var state = FileExplorerState.shared
    @State private var hoveredURL: URL? = nil

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(state.visibleItems) { item in
                    row(item: item)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func row(item: FileItem) -> some View {
        let isSelected = selectedURL == item.url
        let isExpanded = state.expanded.contains(item.url)

        return Button {
            if item.isDirectory {
                state.toggle(item)
            } else {
                onSelect(item)
            }
        } label: {
            HStack(spacing: 5) {
                HStack(spacing: 0) {
                    Spacer().frame(width: CGFloat(item.depth) * 14 + 8)
                    if item.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }
                }

                Image(systemName: item.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(item.iconColor)
                    .frame(width: 14)

                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(item.isDirectory ? 0.75 : (isSelected ? 1.0 : 0.65)))
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.12)
                            : (hoveredURL == item.url ? Color.white.opacity(0.07) : Color.clear)
                    )
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { h in hoveredURL = h ? item.url : nil }
    }
}
