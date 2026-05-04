import SwiftUI

// MARK: - Sound map (v1: grid + output device nodes)

struct SoundMapView: View {
    @StateObject private var outputDevices = AudioOutputDeviceStore()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                SoundMapGridBackground(size: geo.size)

                if outputDevices.devices.isEmpty {
                    Text("No output devices found")
                        .font(.system(.caption))
                        .foregroundStyle(.white.opacity(0.22))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(alignment: .trailing, spacing: 10) {
                    ForEach(outputDevices.devices) { dev in
                        SoundMapOutputDeviceNode(name: dev.name)
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.top, TitleBarLayout.dragStripHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid

private struct SoundMapGridBackground: View {
    var size: CGSize

    private let spacing: CGFloat = 24
    private let lineOpacity: Double = 0.06

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            var path = Path()
            var x: CGFloat = 0
            while x <= w {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: h))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= h {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(.white.opacity(lineOpacity)), lineWidth: 0.5)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(white: 0.04))
    }
}

// MARK: - Node

private struct SoundMapOutputDeviceNode: View {
    var name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SidebarCategory.sound.color.opacity(0.75))
            Text(name)
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .frame(maxWidth: 220, alignment: .trailing)
    }
}
