import Foundation
import SwiftUI

@MainActor
final class UIScaleController: ObservableObject {
    @Published private(set) var scale: Double

    init(initialScale: Double = AppSettings.uiScale) {
        scale = AppSettings.normalizeUIScale(initialScale)
    }

    var isDefaultScale: Bool {
        abs(scale - AppSettings.defaultUIScale) < 0.001
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch scale {
        case ..<0.95:
            return .small
        case ..<1.05:
            return .large
        case ..<1.15:
            return .xLarge
        case ..<1.25:
            return .xxLarge
        case ..<1.35:
            return .xxxLarge
        case ..<1.50:
            return .accessibility1
        case ..<1.70:
            return .accessibility2
        case ..<1.90:
            return .accessibility3
        case ..<2.10:
            return .accessibility4
        default:
            return .accessibility5
        }
    }

    var controlSize: ControlSize {
        switch scale {
        case ..<0.95:
            return .small
        case ..<1.15:
            return .regular
        default:
            return .large
        }
    }

    func scaledMetric(_ baseValue: CGFloat) -> CGFloat {
        baseValue * CGFloat(scale)
    }

    func setScale(_ newValue: Double) {
        let normalized = AppSettings.normalizeUIScale(newValue)
        guard abs(normalized - scale) > 0.001 else { return }
        scale = normalized
        AppSettings.uiScale = normalized
    }

    func zoomIn() {
        setScale(scale + AppSettings.uiScaleStep)
    }

    func zoomOut() {
        setScale(scale - AppSettings.uiScaleStep)
    }

    func reset() {
        setScale(AppSettings.defaultUIScale)
    }
}
