import SwiftUI

struct WellnessBreakOverlayView: View {
    let prompt: WellnessBreakOverlayController.Prompt
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.99, green: 0.96, blue: 0.90).opacity(0.97),
                            Color(red: 0.96, green: 0.88, blue: 0.78).opacity(0.90),
                            Color.black.opacity(0.46)
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 1200
                    )
                )
                .ignoresSafeArea()

            VStack(spacing: 24) {
                AnimatedFlower()
                    .frame(width: 250, height: 250)

                VStack(spacing: 10) {
                    Text(prompt.title)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text(prompt.message)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)

                    Text("Take a minute. Blink. Breathe. Look far away.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.92))
                }

                Button("I Took a Break") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 42)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 36, y: 18)
            )
            .padding(48)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
    }
}

private struct AnimatedFlower: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 1 + 0.08 * sin(t * 1.8)
            let swirl = Angle.degrees(sin(t * 0.55) * 8)

            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    let angle = Angle.degrees(Double(index) * 30) + swirl
                    let petalScale = 0.92 + 0.14 * sin(t * 1.6 + Double(index) * 0.35)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.78, blue: 0.56),
                                    Color(red: 0.97, green: 0.47, blue: 0.44),
                                    Color(red: 0.84, green: 0.31, blue: 0.47)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 50, height: 122)
                        .scaleEffect(petalScale)
                        .offset(y: -46)
                        .rotationEffect(angle)
                        .shadow(color: Color(red: 0.85, green: 0.3, blue: 0.4).opacity(0.22), radius: 10, y: 5)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.94, blue: 0.54),
                                Color(red: 0.96, green: 0.70, blue: 0.20)
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 44
                        )
                    )
                    .frame(width: 74, height: 74)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.45), lineWidth: 2)
                    )
                    .shadow(color: Color.yellow.opacity(0.25), radius: 14, y: 6)

                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 2)
                    .frame(width: 194, height: 194)
                    .blur(radius: 0.4)
            }
            .scaleEffect(pulse)
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}
