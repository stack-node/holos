import SwiftUI

// MARK: - Holos compact toggle (Modules / dense settings)

/// A short, pill-shaped switch that reads lighter than `ToggleStyle.switch` on macOS and matches Holos’ dark cards.
struct HolosCompactToggleStyle: ToggleStyle {
    var onTint: Color
    var trackWidth: CGFloat = 30
    var trackHeight: CGFloat = 16
    var offTrackOpacity: Double = 0.10

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 10) {
            configuration.label
            Spacer(minLength: 0)
            HolosCompactToggleSwitch(
                isOn: configuration.$isOn,
                onTint: onTint,
                trackWidth: trackWidth,
                trackHeight: trackHeight,
                offTrackOpacity: offTrackOpacity
            )
        }
    }
}

private struct HolosCompactToggleSwitch: View {
    @Binding var isOn: Bool
    var onTint: Color
    var trackWidth: CGFloat
    var trackHeight: CGFloat
    var offTrackOpacity: Double

    @Environment(\.isEnabled) private var isEnabled

    private var thumb: CGFloat { max(10, trackHeight - 4) }
    private var travel: CGFloat { trackWidth - 4 - thumb }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? onTint.opacity(0.48) : Color.white.opacity(offTrackOpacity))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isOn ? 0.12 : 0.06), lineWidth: 0.5)
                )

            Circle()
                .fill(Color(white: 0.94))
                .shadow(color: .black.opacity(0.22), radius: 1.2, y: 0.5)
                .frame(width: thumb, height: thumb)
                .padding(2)
                .offset(x: isOn ? travel : 0)
        }
        .frame(width: trackWidth, height: trackHeight)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.38)
        .animation(.spring(response: 0.2, dampingFraction: 0.86), value: isOn)
        .onTapGesture {
            guard isEnabled else { return }
            isOn.toggle()
        }
    }
}
