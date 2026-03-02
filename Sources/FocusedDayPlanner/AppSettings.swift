import Foundation

enum AppSettings {
    static let notificationsEnabledKey = "settings.notifications_enabled"
    static let skipCarryForwardConfirmKey = "settings.skip_carry_forward_confirm"
    static let ignoreCarryForwardWeekendsKey = "settings.ignore_carry_forward_weekends"
    static let themeTintRedKey = "settings.theme_tint_red"
    static let themeTintGreenKey = "settings.theme_tint_green"
    static let themeTintBlueKey = "settings.theme_tint_blue"
    static let themeTintOpacityKey = "settings.theme_tint_opacity"

    static var notificationsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: notificationsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey)
        }
    }

    static var ignoreCarryForwardWeekends: Bool {
        get {
            if UserDefaults.standard.object(forKey: ignoreCarryForwardWeekendsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: ignoreCarryForwardWeekendsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ignoreCarryForwardWeekendsKey)
        }
    }
}
