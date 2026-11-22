import SwiftUI

struct EdgeCountdown: View {
    let deadline: ContinuousClock.Instant
    let window: Duration
    let waitingForStair: Bool
    let atStart: Bool
    let pausedAt: ContinuousClock.Instant?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let remaining = max(0, (deadline - (pausedAt ?? ContinuousClock.now)) / .seconds(1))
            let fraction = min(1, remaining / max(0.01, window / .seconds(1)))
            let danger = PuzzlePalette.warning
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                    Text(waitingForStair ? "STAIR IN MOTION" : (atStart ? "RECONNECT START" : "CONNECT THE ROAD"))
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                    Spacer(minLength: 6)
                    Text(remaining, format: .number.precision(.fractionLength(1)))
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .monospacedDigit()
                    Text("s").font(.caption.weight(.semibold))
                }
                GeometryReader { meter in
                    Capsule()
                        .fill(danger.opacity(0.23))
                        .overlay(alignment: .leading) {
                            Capsule().fill(danger).frame(width: meter.size.width * fraction)
                        }
                }
                .frame(height: 7)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .foregroundStyle(danger)
            .background(PuzzlePalette.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                let opacity = reduceMotion || remaining > 0.65 ? 0.72 : 0.64 + 0.33 * cos(remaining * 12)
                RoundedRectangle(cornerRadius: 14).strokeBorder(danger.opacity(opacity), lineWidth: 1.5)
            }
            .shadow(color: danger.opacity(0.26), radius: 13)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(waitingForStair ? "Wait for the stair" : (atStart ? "Reconnect Start" : "Connect the road"))
            .accessibilityValue(Text("\(remaining, format: .number.precision(.fractionLength(1))) seconds remaining"))
        }
        .frame(maxWidth: 335)
    }
}
