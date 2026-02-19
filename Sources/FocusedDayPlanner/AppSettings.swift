import Foundation

enum AppSettings {
    static let notificationsEnabledKey = "settings.notifications_enabled"
    static let skipCarryForwardConfirmKey = "settings.skip_carry_forward_confirm"

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
}
