import Foundation

// MARK: - Top-level spec (manifest.widget or widget.json)

struct ExtensionWidgetSpec: Decodable, Equatable {
    var version: Int
    var root: WidgetNode
}

// MARK: - Node tree

enum WidgetNode: Equatable {
    case vstack(WidgetStack)
    case hstack(WidgetStack)
    case text(WidgetText)
    case symbol(WidgetSymbol)
    case button(WidgetButton)
    case spacer(WidgetSpacer)
    case whenEmpty(WidgetWhenEmpty)
}

extension WidgetNode: Decodable {
    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .type).lowercased()
        switch kind {
        case "vstack":  self = .vstack(try WidgetStack(from: decoder))
        case "hstack":  self = .hstack(try WidgetStack(from: decoder))
        case "text":    self = .text(try WidgetText(from: decoder))
        case "symbol":  self = .symbol(try WidgetSymbol(from: decoder))
        case "button":  self = .button(try WidgetButton(from: decoder))
        case "spacer":  self = .spacer(try WidgetSpacer(from: decoder))
        case "whenempty": self = .whenEmpty(try WidgetWhenEmpty(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown widget node type \"\(kind)\""
            )
        }
    }
}

// MARK: - Stack

struct WidgetStack: Decodable, Equatable {
    var spacing: Double?
    /// For `vstack`: leading | center | trailing (horizontal alignment of children).
    var horizontalAlignment: String?
    /// For `hstack`: top | center | bottom (vertical alignment of children).
    var verticalAlignment: String?
    var horizontalPadding: Double?
    var children: [WidgetNode]
}

// MARK: - Text

struct WidgetText: Decodable, Equatable {
    /// Static label (mutually exclusive with `binding` in practice).
    var text: String?
    /// Key into `HolosExtension.widgetData`.
    var binding: String?
    var fontSize: Double?
    /// e.g. medium, semibold
    var fontWeight: String?
    /// monospaced | default
    var design: String?
    /// Named text style: caption2, caption, body, callout (overrides fontSize when set).
    var textStyle: String?
    var foregroundOpacity: Double?
    var lineLimit: Int?
    var horizontalPadding: Double?
}

// MARK: - SF Symbol

struct WidgetSymbol: Decodable, Equatable {
    var systemName: String
    var fontSize: Double?
    var fontWeight: String?
    var foregroundRGB: [Double]?
    var foregroundOpacity: Double?
    var horizontalPadding: Double?
}

// MARK: - Button

struct WidgetButtonIconWhen: Decodable, Equatable {
    var binding: String
    var equals: String
    var icon: String
}

struct WidgetButton: Decodable, Equatable {
    var icon: String
    var command: String
    var iconWhen: WidgetButtonIconWhen?
    /// When true, expands horizontally inside parent stacks (media-style row).
    var fillWidth: Bool?
    var horizontalPadding: Double?
}

// MARK: - Spacer

struct WidgetSpacer: Decodable, Equatable {
    var minLength: Double?
}

// MARK: - Conditional branch

struct WidgetWhenEmpty: Decodable, Equatable {
    var binding: String
    var whenEmpty: [WidgetNode]
    var elseNodes: [WidgetNode]

    enum CodingKeys: String, CodingKey {
        case binding, whenEmpty
        case elseNodes = "else"
    }
}
