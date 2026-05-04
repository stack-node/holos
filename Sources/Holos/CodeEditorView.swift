import SwiftUI
import AppKit

// MARK: - SwiftUI wrapper

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var language: CodeLanguage = .swift

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.backgroundColor = .clear
        scroll.drawsBackground = false

        let tv = buildTextView(coordinator: context.coordinator)
        context.coordinator.textView = tv

        let ruler = LineNumberRulerView(textView: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text {
            tv.string = text
            context.coordinator.highlight(tv)
        }
    }

    private func buildTextView(coordinator: Coordinator) -> NSTextView {
        let tv = NSTextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textColor = NSColor.white.withAlphaComponent(0.85)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainerInset = NSSize(width: 8, height: 12)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                  height: CGFloat.greatestFiniteMagnitude)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.delegate = coordinator
        tv.string = ""
        return tv
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: NSTextView?

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv)
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func highlight(_ tv: NSTextView) {
            let source = tv.string
            guard let storage = tv.textStorage else { return }
            let range = NSRange(source.startIndex..., in: source)

            let base = NSMutableAttributedString(string: source)
            base.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.82),
            ], range: range)

            for rule in parent.language.rules {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
                regex.enumerateMatches(in: source, range: range) { match, _, _ in
                    guard let r = match?.range else { return }
                    let captureRange = match?.numberOfRanges ?? 0 > 1 ? match!.range(at: 1) : r
                    if captureRange.location != NSNotFound {
                        base.addAttribute(.foregroundColor, value: rule.color, range: captureRange)
                    }
                }
            }

            let selected = tv.selectedRanges
            storage.beginEditing()
            storage.setAttributedString(base)
            storage.endEditing()
            tv.selectedRanges = selected
        }
    }
}

// MARK: - Syntax rules

enum CodeLanguage {
    case swift, python, javascript, plainText

    var rules: [SyntaxRule] { SyntaxRule.rules(for: self) }

    /// Stable string for persistence (`DevelopmentSessionStore`).
    var persistenceKey: String {
        switch self {
        case .swift: return "swift"
        case .python: return "python"
        case .javascript: return "javascript"
        case .plainText: return "plainText"
        }
    }

    init?(persistenceKey: String) {
        switch persistenceKey {
        case "swift": self = .swift
        case "python": self = .python
        case "javascript": self = .javascript
        case "plainText": self = .plainText
        default: return nil
        }
    }
}

struct SyntaxRule {
    let pattern: String
    let color: NSColor
    var options: NSRegularExpression.Options = []

    static func rules(for lang: CodeLanguage) -> [SyntaxRule] {
        switch lang {
        case .plainText: return []
        case .swift:     return swiftRules
        case .python:    return pythonRules
        case .javascript: return jsRules
        }
    }

    // Colors — tuned to app's dark palette
    private static let colorKeyword  = NSColor(red: 0.78, green: 0.50, blue: 1.00, alpha: 1)
    private static let colorString   = NSColor(red: 0.60, green: 0.90, blue: 0.55, alpha: 1)
    private static let colorComment  = NSColor.white.withAlphaComponent(0.35)
    private static let colorNumber   = NSColor(red: 0.40, green: 0.85, blue: 1.00, alpha: 1)
    private static let colorType     = NSColor(red: 0.55, green: 0.80, blue: 1.00, alpha: 1)
    private static let colorLiteral  = NSColor(red: 1.00, green: 0.65, blue: 0.40, alpha: 1)

    private static let swiftKeywords = [
        "import", "struct", "class", "enum", "protocol", "extension", "func",
        "var", "let", "if", "else", "guard", "return", "switch", "case",
        "default", "for", "in", "while", "do", "try", "catch", "throw",
        "throws", "async", "await", "actor", "nonisolated", "init", "deinit",
        "override", "final", "static", "private", "public", "internal", "open",
        "fileprivate", "mutating", "lazy", "weak", "unowned", "inout", "some",
        "any", "where", "as", "is", "nil", "true", "false", "Self", "self",
        "super", "typealias", "associatedtype", "continue", "break", "defer",
        "@State", "@Binding", "@ObservedObject", "@Published", "@ViewBuilder",
        "@MainActor", "@escaping", "@discardableResult", "@objc",
    ]

    private static var swiftRules: [SyntaxRule] {
        let kw = "\\b(" + swiftKeywords.map(NSRegularExpression.escapedPattern).joined(separator: "|") + ")\\b"
        return [
            SyntaxRule(pattern: "//.*$",                         color: colorComment, options: .anchorsMatchLines),
            SyntaxRule(pattern: "/\\*[\\s\\S]*?\\*/",            color: colorComment),
            SyntaxRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"",      color: colorString),
            SyntaxRule(pattern: "\"\"\"[\\s\\S]*?\"\"\"",        color: colorString),
            SyntaxRule(pattern: kw,                              color: colorKeyword),
            SyntaxRule(pattern: "\\b[A-Z][A-Za-z0-9_]*\\b",     color: colorType),
            SyntaxRule(pattern: "\\b\\d+\\.?\\d*\\b",           color: colorNumber),
            SyntaxRule(pattern: "#(available|if|else|endif|selector|imageLiteral|colorLiteral|fileID|filePath|line|column|function)\\b", color: colorLiteral),
        ]
    }

    private static let pyKeywords = [
        "and", "as", "assert", "async", "await", "break", "class", "continue",
        "def", "del", "elif", "else", "except", "False", "finally", "for",
        "from", "global", "if", "import", "in", "is", "lambda", "None",
        "nonlocal", "not", "or", "pass", "raise", "return", "True", "try",
        "while", "with", "yield",
    ]

    private static var pythonRules: [SyntaxRule] {
        let kw = "\\b(" + pyKeywords.joined(separator: "|") + ")\\b"
        return [
            SyntaxRule(pattern: "#.*$",                          color: colorComment, options: .anchorsMatchLines),
            SyntaxRule(pattern: "\"\"\"[\\s\\S]*?\"\"\"",        color: colorString),
            SyntaxRule(pattern: "'''[\\s\\S]*?'''",              color: colorString),
            SyntaxRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"",      color: colorString),
            SyntaxRule(pattern: "'(?:[^'\\\\]|\\\\.)*'",         color: colorString),
            SyntaxRule(pattern: kw,                              color: colorKeyword),
            SyntaxRule(pattern: "\\b[A-Z][A-Za-z0-9_]*\\b",     color: colorType),
            SyntaxRule(pattern: "\\b\\d+\\.?\\d*\\b",           color: colorNumber),
            SyntaxRule(pattern: "@[A-Za-z_][A-Za-z0-9_]*",      color: colorLiteral),
        ]
    }

    private static let jsKeywords = [
        "break", "case", "catch", "class", "const", "continue", "debugger",
        "default", "delete", "do", "else", "export", "extends", "false",
        "finally", "for", "function", "if", "import", "in", "instanceof",
        "let", "new", "null", "return", "static", "super", "switch", "this",
        "throw", "true", "try", "typeof", "undefined", "var", "void",
        "while", "with", "yield", "async", "await", "of", "from", "as",
    ]

    private static var jsRules: [SyntaxRule] {
        let kw = "\\b(" + jsKeywords.joined(separator: "|") + ")\\b"
        return [
            SyntaxRule(pattern: "//.*$",                         color: colorComment, options: .anchorsMatchLines),
            SyntaxRule(pattern: "/\\*[\\s\\S]*?\\*/",            color: colorComment),
            SyntaxRule(pattern: "`(?:[^`\\\\]|\\\\.)*`",         color: colorString),
            SyntaxRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"",      color: colorString),
            SyntaxRule(pattern: "'(?:[^'\\\\]|\\\\.)*'",         color: colorString),
            SyntaxRule(pattern: kw,                              color: colorKeyword),
            SyntaxRule(pattern: "\\b[A-Z][A-Za-z0-9_]*\\b",     color: colorType),
            SyntaxRule(pattern: "\\b\\d+\\.?\\d*\\b",           color: colorNumber),
        ]
    }
}

// MARK: - Line number ruler

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    private let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private let textColor = NSColor.white.withAlphaComponent(0.28)
    private let backgroundColor = NSColor.clear

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.ruleThickness = 36
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func textDidChange() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.set()
        dirtyRect.fill()

        guard let tv = textView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }

        let visibleRect = tv.enclosingScrollView?.contentView.bounds ?? tv.visibleRect
        let inset = tv.textContainerInset
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let charRange  = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let text       = tv.string as NSString

        var lineNumber = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location),
                                 options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        var glyphIdx = glyphRange.location
        let end = NSMaxRange(glyphRange)
        var charIdx = charRange.location

        while glyphIdx < end {
            var lineGlyphRange = NSRange()
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &lineGlyphRange)
            let lineCharRange = lm.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)

            let y = lineRect.minY + inset.height - visibleRect.origin.y
            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - labelSize.width - 6, y: y + 1), withAttributes: attrs)

            let nextCharIdx = NSMaxRange(lineCharRange)
            if nextCharIdx > charIdx {
                let substring = text.substring(with: NSRange(location: charIdx, length: nextCharIdx - charIdx))
                let newlines = substring.filter { $0 == "\n" }.count
                lineNumber += max(newlines, 1)
                charIdx = nextCharIdx
            }

            glyphIdx = NSMaxRange(lineGlyphRange)
        }

        NSColor.white.withAlphaComponent(0.08).set()
        NSRect(x: ruleThickness - 0.5, y: dirtyRect.minY, width: 0.5, height: dirtyRect.height).fill()
    }
}
