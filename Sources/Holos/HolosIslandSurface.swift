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

    static func from(zoneID: String) -> HolosWidgetZoneChromePosition {
        switch zoneID {
        case "above-left-sidebar": return .aboveSidebarStrip
        case "below-left-sidebar": return .belowSidebarStrip
        default: return .besideSidebar
        }
    }
}

// MARK: - Island surfaces (left sidebar sections + pinned extension widgets)

/// Top “frosted” layer: same treatment as each section card in `SidebarContentView`.
struct HolosIslandSurface: View {
    var cornerRadius: CGFloat = 9

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            )
    }
}

/// Column tint + island. Pass `position` from the host — `.background { }` often does not inherit `@Environment`, so we take an explicit value.
struct HolosWidgetIslandChrome: View {
    @ObservedObject private var config = HolosConfig.shared

    var position: HolosWidgetZoneChromePosition
    /// Matches sidebar island cards and main panel rounding (~12).
    var cornerRadius: CGFloat = 12

    var body: some View {
        let r = cornerRadius
        Group {
            switch position {
            case .besideSidebar:
                roundedStack(r: r)
            case .aboveSidebarStrip:
                unevenStack(
                    UnevenRoundedRectangle(
                        topLeadingRadius: r,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: r,
                        style: .continuous
                    )
                )
            case .belowSidebarStrip:
                unevenStack(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: r,
                        bottomTrailingRadius: r,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
            }
        }
        .compositingGroup()
    }

    private func roundedStack(r: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(baseFill)
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color.white.opacity(0.04))
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
        }
    }

    private func unevenStack(_ shape: UnevenRoundedRectangle) -> some View {
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
