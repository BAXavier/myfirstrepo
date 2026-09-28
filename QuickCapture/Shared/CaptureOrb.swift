import SwiftUI

/// Pulsing orb shared by the HUD, iPhone and Watch.
struct CaptureOrb: View {
    var listening: Bool
    var level: Float
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(listening ? Color.red.opacity(0.25) : Color.accentColor.opacity(0.15))
                .scaleEffect(listening ? 1 + CGFloat(level) * 0.6 : 1)
                .animation(.easeOut(duration: 0.12), value: level)
            Circle()
                .fill(listening ? Color.red : Color.accentColor)
                .frame(width: size * 0.62, height: size * 0.62)
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: size * 0.26, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: listening)
        }
        .frame(width: size, height: size)
    }
}
