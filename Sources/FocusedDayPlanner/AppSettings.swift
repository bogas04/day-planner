import Foundation

enum AppSettings {
    static let notificationsEnabledKey = "settings.notifications_enabled"
    static let wellnessBreakRemindersEnabledKey = "settings.wellness_break_reminders_enabled"
    static let wellnessBreakIntervalMinutesKey = "settings.wellness_break_interval_minutes"
    static let skipCarryForwardConfirmKey = "settings.skip_carry_forward_confirm"
    static let ignoreCarryForwardWeekendsKey = "settings.ignore_carry_forward_weekends"
    static let themeTintRedKey = "settings.theme_tint_red"
    static let themeTintGreenKey = "settings.theme_tint_green"
    static let themeTintBlueKey = "settings.theme_tint_blue"
    static let themeTintOpacityKey = "settings.theme_tint_opacity"
    static let uiScaleKey = "settings.ui_scale"
    static let backgroundAudioEnabledKey = "settings.background_audio_enabled"
    static let backgroundAudioSelectedItemIDKey = "settings.background_audio_selected_item_id"
    static let backgroundAudioMasterVolumeKey = "settings.background_audio_master_volume"
    static let backgroundAudioSelectedFilterKey = "settings.background_audio_selected_filter"
    static let backgroundAudioAutoResumeKey = "settings.background_audio_auto_resume"

    static let defaultUIScale = 1.0
    static let minimumUIScale = 0.85
    static let uiScaleStep = 0.05
    static let defaultBackgroundAudioVolume = 0.72
    static let defaultWellnessBreakIntervalMinutes = 30
    static let minimumWellnessBreakIntervalMinutes = 10
    static let maximumWellnessBreakIntervalMinutes = 180
    static let wellnessBreakIntervalStepMinutes = 5

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

    static var wellnessBreakRemindersEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: wellnessBreakRemindersEnabledKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: wellnessBreakRemindersEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: wellnessBreakRemindersEnabledKey)
        }
    }

    static var wellnessBreakIntervalMinutes: Int {
        get {
            let storedValue = UserDefaults.standard.integer(forKey: wellnessBreakIntervalMinutesKey)
            if storedValue == 0 {
                return defaultWellnessBreakIntervalMinutes
            }
            return normalizeWellnessBreakIntervalMinutes(storedValue)
        }
        set {
            UserDefaults.standard.set(
                normalizeWellnessBreakIntervalMinutes(newValue),
                forKey: wellnessBreakIntervalMinutesKey
            )
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

    static var uiScale: Double {
        get {
            let storedValue = UserDefaults.standard.double(forKey: uiScaleKey)
            if storedValue == 0 {
                return defaultUIScale
            }
            return normalizeUIScale(storedValue)
        }
        set {
            UserDefaults.standard.set(normalizeUIScale(newValue), forKey: uiScaleKey)
        }
    }

    static var backgroundAudioEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: backgroundAudioEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: backgroundAudioEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: backgroundAudioEnabledKey)
        }
    }

    static var backgroundAudioSelectedItemID: String? {
        get {
            UserDefaults.standard.string(forKey: backgroundAudioSelectedItemIDKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: backgroundAudioSelectedItemIDKey)
        }
    }

    static var backgroundAudioMasterVolume: Double {
        get {
            guard UserDefaults.standard.object(forKey: backgroundAudioMasterVolumeKey) != nil else {
                return defaultBackgroundAudioVolume
            }
            let storedValue = UserDefaults.standard.double(forKey: backgroundAudioMasterVolumeKey)
            return normalizeBackgroundAudioVolume(storedValue)
        }
        set {
            UserDefaults.standard.set(
                normalizeBackgroundAudioVolume(newValue),
                forKey: backgroundAudioMasterVolumeKey
            )
        }
    }

    static var backgroundAudioSelectedFilter: String {
        get {
            UserDefaults.standard.string(forKey: backgroundAudioSelectedFilterKey) ?? "curated"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: backgroundAudioSelectedFilterKey)
        }
    }

    static var backgroundAudioAutoResume: Bool {
        get {
            if UserDefaults.standard.object(forKey: backgroundAudioAutoResumeKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: backgroundAudioAutoResumeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: backgroundAudioAutoResumeKey)
        }
    }

    static func normalizeUIScale(_ rawValue: Double) -> Double {
        let clampedValue = max(rawValue, minimumUIScale)
        let steppedValue = (clampedValue / uiScaleStep).rounded() * uiScaleStep
        return (steppedValue * 100).rounded() / 100
    }

    static func normalizeBackgroundAudioVolume(_ rawValue: Double) -> Double {
        min(max(rawValue, 0), 1)
    }

    static func normalizeWellnessBreakIntervalMinutes(_ rawValue: Int) -> Int {
        let clampedValue = max(minimumWellnessBreakIntervalMinutes, min(rawValue, maximumWellnessBreakIntervalMinutes))
        let remainder = clampedValue % wellnessBreakIntervalStepMinutes
        if remainder == 0 {
            return clampedValue
        }

        let roundedValue = clampedValue + (wellnessBreakIntervalStepMinutes - remainder)
        return min(roundedValue, maximumWellnessBreakIntervalMinutes)
    }
}
