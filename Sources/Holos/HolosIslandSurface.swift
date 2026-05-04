import SwiftUI

// MARK: - Pinned widget zone (drives corner shape for extension cards)

/// Which edge of the Holos window cluster the widget panel sits on — only the “outer” corners stay round where the card meets the desktop; inner edges stay square against the sidebar strip.
enum HolosWidgetZoneChromePosition: Equatable {
    /// `left-of-left-sidebar` vertical stack.
    case besideSidebar
    /// `above-left-sidebar` horizontal strip — round top, flush flat bottom against the category bar.
    case aboveSidebarStrip
    /// `below-left-sidebar` horizontal strip — flat top, round bottom.
    case belowSidebarStrip
}

private struct HolosWidgetZoneChromePositionKey: EnvironmentKey {
    static let defaultValue: HolosWidgetZoneChromePosition = .besideSidebar
}

extension EnvironmentValues {
    var holosWidgetZoneChromePosition: HolosWidgetZoneChromePosition {
        get { self[HolosWidgetZoneChromePositionKey.self] }
        set { self[HolosWidgetZoneChromePositionKey.self] = newValue }
    }
}

// MARK: - Island surfaces (left sidebar sections + pinned extension widgets)

/// Top “frosted” layer: same treatment as each section card in `SidebarContentView`.
struct HolosIslandSurface: View {
    var cornerRadius: CGFloat = 9

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            )
    }
}

/// Column tint + island, matching the sidebar stack. Corners follow `holosWidgetZoneChromePosition`.
struct HolosWidgetIslandChrome: View {
    @ObservedObject private var config = HolosConfig.shared
    @Environment(\.holosWidgetZoneChromePosition) private var zonePosition

    var cornerRadius: CGFloat = 9

    var body: some View {
        let shape = zonePosition.islandShape(cornerRadius: cornerRadius)
        ZStack {
            shape.fill(baseFill)
            shape.fill(Color.white.opacity(0.04))
            shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var baseFill: Color {
        if config.blurEnabled {
            return Color.black.opacity(config.backgroundOpacity * 0.42)
        }
        return Color(white: 0.08).opacity(0.55)
    }
}

private extension HolosWidgetZoneChromePosition {
    func islandShape(cornerRadius r: CGFloat) -> UnevenRoundedRectangle {
        switch self {
        case .besideSidebar:
            return UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: r,
                bottomTrailingRadius: r,
                topTrailingRadius: r
            )
        case .aboveSidebarStrip:
            return UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: r
            )
        case .belowSidebarStrip:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: r,
                bottomTrailingRadius: r,
                topTrailingRadius: 0
            )
        }
    }
}
