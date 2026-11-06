import SwiftUI

/// The colours of the AI glow: brand orange into pink and violet.
enum AIGlow {
    static let colors: [Color] = [
        .notchAccent, Color(red: 1, green: 0.25, blue: 0.5), Color(red: 0.55, green: 0.35, blue: 1),
        Color(red: 0.2, green: 0.6, blue: 1), .notchAccent,
    ]

    static func gradient(angle: Double) -> AngularGradient {
        AngularGradient(colors: colors, center: .center, angle: .degrees(angle))
    }
}

/// Shown while the AI works: a spinning colour orb and a shimmering status line that changes as time passes.
struct ThinkingView: View {
    let providerName: String
    @State private var start = Date()

    private static let steps = ["Reading your clip", "Thinking", "Choosing the words", "Almost there"]

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            VStack(spacing: 14) {
                orb(elapsed)
                shimmerText(Self.steps[min(Int(elapsed / 1.8), Self.steps.count - 1)], phase: elapsed)
                Text(providerName)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func orb(_ t: Double) -> some View {
        ZStack {
            Circle()
                .fill(AIGlow.gradient(angle: t * 140))
                .frame(width: 46, height: 46)
                .blur(radius: 14)
                .opacity(0.9)
            Circle()
                .strokeBorder(AIGlow.gradient(angle: -t * 220), lineWidth: 3)
                .frame(width: 34, height: 34)
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(1 + 0.12 * sin(t * 4))
        }
    }

    private func shimmerText(_ text: String, phase: Double) -> some View {
        let x = (phase.truncatingRemainder(dividingBy: 1.6)) / 1.6
        return Text(text + "…")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, x - 0.25)),
                        .init(color: .white, location: x),
                        .init(color: .clear, location: min(1, x + 0.25)),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .mask(Text(text + "…").font(.system(size: 13, weight: .semibold)))
            }
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: text)
    }
}

/// A rotating colour border around the whole notch panel while the AI is busy.
struct AIGlowBorder: View {
    let radius: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate * 160
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .strokeBorder(AIGlow.gradient(angle: angle), lineWidth: 2)
                .blur(radius: 1)
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                        .strokeBorder(AIGlow.gradient(angle: angle), lineWidth: 6)
                        .blur(radius: 10)
                        .opacity(0.6)
                )
        }
        .allowsHitTesting(false)
    }
}

/// A blinking caret at the end of text that's still being written.
struct WritingCaret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.notchAccent)
                .frame(width: 2, height: 13)
                .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
        }
    }
}
