import Foundation

enum AppSettings {
    static let notificationsEnabledKey = "settings.notifications_enabled"
    static let todoReminderIntervalMinutesKey = "settings.todo_reminder_interval_minutes"
    static let todoReminderMessageKey = "settings.todo_reminder_message"
    static let emptyDayReminderMessageKey = "settings.empty_day_reminder_message"
    static let wellnessBreakRemindersEnabledKey = "settings.wellness_break_reminders_enabled"
    static let wellnessBreakIntervalMinutesKey = "settings.wellness_break_interval_minutes"
    static let wellnessBreakMessageKey = "settings.wellness_break_message"
    static let wellnessBreakStartMinutesKey = "settings.wellness_break_start_minutes"
    static let wellnessBreakEndMinutesKey = "settings.wellness_break_end_minutes"
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
    static let developerModeEnabledKey = "settings.developer_mode_enabled"

    static let defaultUIScale = 1.0
    static let minimumUIScale = 0.85
    static let uiScaleStep = 0.05
    static let defaultBackgroundAudioVolume = 0.72
    static let defaultTodoReminderIntervalMinutes = 60
    static let defaultTodoReminderMessage = "You still have {count} todo(s) left. Pick one and keep going."
    static let defaultEmptyDayReminderMessage = "What would you like to work on today?"
    static let minimumTodoReminderIntervalMinutes = 15
    static let maximumTodoReminderIntervalMinutes = 180
    static let todoReminderIntervalStepMinutes = 15
    static let defaultWellnessBreakIntervalMinutes = 30
    static let defaultWellnessBreakMessage = "Stand up, stretch, or let your eyes rest on something far away for a moment."
    static let defaultWellnessBreakStartMinutes = 9 * 60
    static let defaultWellnessBreakEndMinutes = 18 * 60
    static let minimumWellnessBreakIntervalMinutes = 1
    static let maximumWellnessBreakIntervalMinutes = 180
    static let wellnessBreakIntervalStepMinutes = 1

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

    static var todoReminderIntervalMinutes: Int {
        get {
            let storedValue = UserDefaults.standard.integer(forKey: todoReminderIntervalMinutesKey)
            if storedValue == 0 {
                return defaultTodoReminderIntervalMinutes
            }
            return normalizeTodoReminderIntervalMinutes(storedValue)
        }
        set {
            UserDefaults.standard.set(
                normalizeTodoReminderIntervalMinutes(newValue),
                forKey: todoReminderIntervalMinutesKey
            )
        }
    }

    static var todoReminderMessage: String {
        get {
            let storedValue = UserDefaults.standard.string(forKey: todoReminderMessageKey)
            return normalizeTodoReminderMessage(storedValue)
        }
        set {
            UserDefaults.standard.set(
                normalizeTodoReminderMessage(newValue),
                forKey: todoReminderMessageKey
            )
        }
    }

    static var emptyDayReminderMessage: String {
        get {
            let storedValue = UserDefaults.standard.string(forKey: emptyDayReminderMessageKey)
            return normalizeEmptyDayReminderMessage(storedValue)
        }
        set {
            UserDefaults.standard.set(
                normalizeEmptyDayReminderMessage(newValue),
                forKey: emptyDayReminderMessageKey
            )
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

    static var wellnessBreakMessage: String {
        get {
            let storedValue = UserDefaults.standard.string(forKey: wellnessBreakMessageKey)
            return normalizeWellnessBreakMessage(storedValue)
        }
        set {
            UserDefaults.standard.set(
                normalizeWellnessBreakMessage(newValue),
                forKey: wellnessBreakMessageKey
            )
        }
    }

    static var wellnessBreakStartMinutes: Int {
        get {
            let storedValue = UserDefaults.standard.integer(forKey: wellnessBreakStartMinutesKey)
            if storedValue == 0 && UserDefaults.standard.object(forKey: wellnessBreakStartMinutesKey) == nil {
                return defaultWellnessBreakStartMinutes
            }
            return normalizeWellnessBreakStartMinutes(storedValue)
        }
        set {
            UserDefaults.standard.set(
                normalizeWellnessBreakStartMinutes(newValue),
                forKey: wellnessBreakStartMinutesKey
            )
        }
    }

    static var wellnessBreakEndMinutes: Int {
        get {
            let storedValue = UserDefaults.standard.integer(forKey: wellnessBreakEndMinutesKey)
            if storedValue == 0 && UserDefaults.standard.object(forKey: wellnessBreakEndMinutesKey) == nil {
                return defaultWellnessBreakEndMinutes
            }
            return normalizeWellnessBreakEndMinutes(storedValue)
        }
        set {
            UserDefaults.standard.set(
                normalizeWellnessBreakEndMinutes(newValue),
                forKey: wellnessBreakEndMinutesKey
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

    static var developerModeEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: developerModeEnabledKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: developerModeEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: developerModeEnabledKey)
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

    static func normalizeTodoReminderIntervalMinutes(_ rawValue: Int) -> Int {
        let clampedValue = max(minimumTodoReminderIntervalMinutes, min(rawValue, maximumTodoReminderIntervalMinutes))
        let remainder = clampedValue % todoReminderIntervalStepMinutes
        if remainder == 0 {
            return clampedValue
        }

        let roundedValue = clampedValue + (todoReminderIntervalStepMinutes - remainder)
        return min(roundedValue, maximumTodoReminderIntervalMinutes)
    }

    static func normalizeTodoReminderMessage(_ rawValue: String?) -> String {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? defaultTodoReminderMessage : trimmedValue
    }

    static func normalizeEmptyDayReminderMessage(_ rawValue: String?) -> String {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? defaultEmptyDayReminderMessage : trimmedValue
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

    static func normalizeWellnessBreakMessage(_ rawValue: String?) -> String {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? defaultWellnessBreakMessage : trimmedValue
    }

    static func normalizeWellnessBreakStartMinutes(_ rawValue: Int) -> Int {
        let clampedValue = min(max(rawValue, 0), 23 * 60 + 58)
        return clampedValue
    }

    static func normalizeWellnessBreakEndMinutes(_ rawValue: Int) -> Int {
        let clampedValue = min(max(rawValue, 1), 23 * 60 + 59)
        return clampedValue
    }

    static func sanitizeWellnessWorkHours(startMinutes: Int, endMinutes: Int) -> (startMinutes: Int, endMinutes: Int) {
        let normalizedStart = normalizeWellnessBreakStartMinutes(startMinutes)
        let normalizedEnd = normalizeWellnessBreakEndMinutes(endMinutes)
        if normalizedEnd > normalizedStart {
            return (normalizedStart, normalizedEnd)
        }
        return (normalizedStart, min(normalizedStart + 1, 23 * 60 + 59))
    }
}
