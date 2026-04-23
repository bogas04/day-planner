import AppKit
import SwiftUI

struct ReadableProminentButtonStyle: ButtonStyle {
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let isActive = controlActiveState == .key
        let backgroundColor: Color
        let foregroundColor: Color
        let borderColor: Color

        if isEnabled {
            backgroundColor = isActive
                ? Color.accentColor.opacity(isPressed ? 0.82 : 0.92)
                : Color.accentColor.opacity(isPressed ? 0.72 : 0.84)
            foregroundColor = Color.white.opacity(isActive ? 0.99 : 0.96)
            borderColor = Color.white.opacity(isActive ? 0.22 : 0.16)
        } else {
            backgroundColor = Color(nsColor: .controlBackgroundColor).opacity(isActive ? 0.98 : 1.0)
            foregroundColor = Color.primary.opacity(isActive ? 0.55 : 0.46)
            borderColor = Color.black.opacity(isActive ? 0.08 : 0.05)
        }

        return configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: isEnabled
                    ? Color.black.opacity(isActive ? 0.12 : 0.06)
                    : Color.clear,
                radius: isPressed ? 4 : 10,
                y: isPressed ? 1 : 4
            )
            .scaleEffect(isPressed && isEnabled ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
            .animation(.easeOut(duration: 0.12), value: controlActiveState)
    }
}

struct ReadableSecondaryButtonStyle: ButtonStyle {
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let isActive = controlActiveState == .key
        let backgroundColor: Color
        let foregroundColor: Color
        let borderColor: Color

        if isEnabled {
            backgroundColor = Color(nsColor: .controlBackgroundColor)
                .opacity(isPressed ? 0.96 : (isActive ? 0.90 : 0.95))
            foregroundColor = Color.primary.opacity(isActive ? 0.94 : 0.88)
            borderColor = Color.black.opacity(isActive ? 0.12 : 0.09)
        } else {
            backgroundColor = Color(nsColor: .controlBackgroundColor).opacity(0.88)
            foregroundColor = Color.primary.opacity(0.42)
            borderColor = Color.black.opacity(0.05)
        }

        return configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(isEnabled && isActive ? 0.06 : 0.02),
                radius: isPressed ? 2 : 6,
                y: isPressed ? 1 : 2
            )
            .scaleEffect(isPressed && isEnabled ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
            .animation(.easeOut(duration: 0.12), value: controlActiveState)
    }
}
