import Foundation
import UserNotifications

@MainActor
final class DailyReminderScheduler: ObservableObject {
    struct DebugSnapshot {
        let lines: [String]

        var summary: String {
            lines.joined(separator: "\n")
        }
    }

    static let shared = DailyReminderScheduler()
    nonisolated static let wellnessNotificationIdentifierValue = "focuseddayplanner.wellness.break"
    nonisolated static let testNotificationIdentifierValue = "focuseddayplanner.test"

    private var didRequestAuthorization = false
    private var refreshTask: Task<Void, Never>?
    private var lastScheduledState: ReminderScheduleState?
    @Published private(set) var lastNotificationStatus = "No notification action yet."
    @Published private(set) var lastNotificationUpdatedAt: Date?

    private init() {}

    func refresh(totalTodos: Int, pendingTodos: Int, now: Date = .now) {
        guard Self.isSupportedEnvironment else { return }
        guard AppSettings.notificationsEnabled else {
            WellnessBreakOverlayController.shared.configure(
                isEnabled: false,
                intervalMinutes: AppSettings.defaultWellnessBreakIntervalMinutes,
                message: AppSettings.wellnessBreakMessage,
                workdayStartMinutes: AppSettings.wellnessBreakStartMinutes,
                workdayEndMinutes: AppSettings.wellnessBreakEndMinutes,
                skipWeekends: AppSettings.ignoreCarryForwardWeekends
            )
            clearPendingNotifications()
            lastScheduledState = nil
            updateNotificationStatus("Notifications disabled. Cleared pending requests.")
            return
        }
        let state = ReminderScheduleState(
            totalTodos: totalTodos,
            pendingTodos: pendingTodos,
            notificationsEnabled: AppSettings.notificationsEnabled,
            todoReminderIntervalMinutes: AppSettings.todoReminderIntervalMinutes,
            todoReminderMessage: AppSettings.todoReminderMessage,
            emptyDayReminderMessage: AppSettings.emptyDayReminderMessage,
            wellnessBreakEnabled: AppSettings.wellnessBreakRemindersEnabled,
            wellnessBreakIntervalMinutes: AppSettings.wellnessBreakIntervalMinutes,
            wellnessBreakMessage: AppSettings.wellnessBreakMessage,
            wellnessBreakStartMinutes: AppSettings.wellnessBreakStartMinutes,
            wellnessBreakEndMinutes: AppSettings.wellnessBreakEndMinutes,
            ignoreWeekends: AppSettings.ignoreCarryForwardWeekends
        )
        if state == lastScheduledState {
            return
        }
        lastScheduledState = state

        WellnessBreakOverlayController.shared.configure(
            isEnabled: AppSettings.wellnessBreakRemindersEnabled,
            intervalMinutes: AppSettings.wellnessBreakIntervalMinutes,
            message: AppSettings.wellnessBreakMessage,
            workdayStartMinutes: AppSettings.wellnessBreakStartMinutes,
            workdayEndMinutes: AppSettings.wellnessBreakEndMinutes,
            skipWeekends: AppSettings.ignoreCarryForwardWeekends
        )
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard let self else { return }
            await self.ensureAuthorizationRequested()
            await self.schedule(totalTodos: totalTodos, pendingTodos: pendingTodos, now: now)
        }
    }

    func clearPendingNotifications() {
        guard let center = notificationCenter() else { return }
        center.removePendingNotificationRequests(withIdentifiers: allNotificationIdentifiers)
        updateNotificationStatus("Cleared pending notifications.")
    }

    func sendTestNotification() async -> DebugSnapshot {
        guard Self.isSupportedEnvironment else {
            return DebugSnapshot(lines: [
                "Environment: unsupported",
                "Reason: notifications only work from the packaged macOS app."
            ])
        }

        await ensureAuthorizationRequested()
        let beforeSettings = await currentNotificationSettings()
        var lines = debugLines(for: beforeSettings, prefix: "Before")

        guard beforeSettings.authorizationStatus == .authorized || beforeSettings.authorizationStatus == .provisional else {
            lines.append("Schedule result: skipped because notification permission is not granted.")
            updateNotificationStatus("Skipped test notification because permission is not granted.")
            return DebugSnapshot(lines: lines)
        }

        let scheduled = await addNotification(
            id: testNotificationIdentifier,
            date: Date().addingTimeInterval(1),
            body: "This is a test reminder from Focused Day Planner."
        )
        lines.append("Schedule result: \(scheduled ? "queued test notification for ~1 second from now." : "failed to queue test notification.")")
        updateNotificationStatus(scheduled ? "Queued a test notification." : "Failed to queue a test notification.")
        await MainActor.run {
            WellnessBreakOverlayController.shared.show(
                title: "Test reminder",
                message: "This is what a wellness break overlay looks like."
            )
        }

        let pendingIdentifiers = await pendingNotificationIdentifiers()
        if pendingIdentifiers.isEmpty {
            lines.append("Pending requests: none")
        } else {
            lines.append("Pending requests: \(pendingIdentifiers.joined(separator: ", "))")
        }

        return DebugSnapshot(lines: lines)
    }

    func permissionDebugSnapshot() async -> DebugSnapshot {
        guard Self.isSupportedEnvironment else {
            return DebugSnapshot(lines: [
                "Environment: unsupported",
                "Reason: notifications only work from the packaged macOS app."
            ])
        }

        let settings = await currentNotificationSettings()
        var lines = debugLines(for: settings, prefix: "Current")
        let pendingIdentifiers = await pendingNotificationIdentifiers()
        if pendingIdentifiers.isEmpty {
            lines.append("Pending requests: none")
        } else {
            lines.append("Pending requests: \(pendingIdentifiers.joined(separator: ", "))")
        }
        return DebugSnapshot(lines: lines)
    }

    private func ensureAuthorizationRequested() async {
        guard let center = notificationCenter() else { return }
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Keep app functional even if notifications cannot be requested.
        }
    }

    private func schedule(totalTodos: Int, pendingTodos: Int, now: Date) async {
        guard let center = notificationCenter() else { return }
        center.removePendingNotificationRequests(withIdentifiers: allNotificationIdentifiers)

        if AppSettings.wellnessBreakRemindersEnabled {
            await addWellnessNotifications(now: now)
        }

        if totalTodos == 0 {
            if let date = nextDate(minutesSinceMidnight: 11 * 60, now: now) {
                _ = await addNotification(
                    id: "focuseddayplanner.empty.11",
                    date: date,
                    body: AppSettings.emptyDayReminderMessage
                )
            }
            return
        }

        guard pendingTodos > 0 else { return }

        let intervalMinutes = AppSettings.normalizeTodoReminderIntervalMinutes(AppSettings.todoReminderIntervalMinutes)
        let reminderBody = AppSettings
            .normalizeTodoReminderMessage(AppSettings.todoReminderMessage)
            .replacingOccurrences(of: "{count}", with: "\(pendingTodos)")

        var reminderMinute = 11 * 60
        while reminderMinute <= 17 * 60 {
            guard let date = nextDate(minutesSinceMidnight: reminderMinute, now: now) else {
                reminderMinute += intervalMinutes
                continue
            }
            _ = await addNotification(
                id: "focuseddayplanner.pending.\(reminderMinute)",
                date: date,
                body: reminderBody
            )
            reminderMinute += intervalMinutes
        }
    }

    private func notificationCenter() -> UNUserNotificationCenter? {
        guard Self.isSupportedEnvironment else { return nil }
        return UNUserNotificationCenter.current()
    }

    private static var isSupportedEnvironment: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private func addNotification(id: String, date: Date, body: String) async -> Bool {
        guard let center = notificationCenter() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Focused Day Planner"
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            // Ignore failures to avoid breaking planner workflows.
            return false
        }
    }

    private func addWellnessNotifications(now: Date) async {
        let calendar = Calendar.current
        let sanitizedHours = AppSettings.sanitizeWellnessWorkHours(
            startMinutes: AppSettings.wellnessBreakStartMinutes,
            endMinutes: AppSettings.wellnessBreakEndMinutes
        )
        let intervalMinutes = max(AppSettings.wellnessBreakIntervalMinutes, 1)
        var scheduledCount = 0

        for dayOffset in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            if AppSettings.ignoreCarryForwardWeekends && calendar.isDateInWeekend(dayDate) {
                continue
            }

            var currentMinutes = sanitizedHours.startMinutes + intervalMinutes
            while currentMinutes < sanitizedHours.endMinutes {
                guard let candidateDate = date(
                    at: currentMinutes,
                    on: dayDate,
                    calendar: calendar
                ) else {
                    currentMinutes += intervalMinutes
                    continue
                }

                if candidateDate > now {
                    let didSchedule = await addNotification(
                        id: wellnessNotificationIdentifier(for: candidateDate),
                        date: candidateDate,
                        body: AppSettings.wellnessBreakMessage
                    )
                    if didSchedule {
                        scheduledCount += 1
                    }
                }

                currentMinutes += intervalMinutes
            }
        }

        if scheduledCount > 0 {
            updateNotificationStatus("Queued \(scheduledCount) wellness reminder(s) within work hours.")
        } else {
            updateNotificationStatus("No wellness reminders were queued in the current work window.")
        }
    }

    private func date(at minutesSinceMidnight: Int, on date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = minutesSinceMidnight / 60
        components.minute = minutesSinceMidnight % 60
        components.second = 0
        return calendar.date(from: components)
    }

    private func addRepeatingNotification(id: String, timeInterval: TimeInterval, body: String) async {
        guard let center = notificationCenter() else { return }
        guard timeInterval >= 60 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Focused Day Planner"
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // Ignore failures to avoid breaking planner workflows.
        }
    }

    private func nextDate(minutesSinceMidnight: Int, now: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = minutesSinceMidnight / 60
        components.minute = minutesSinceMidnight % 60
        components.second = 0

        guard let candidate = calendar.date(from: components) else { return nil }
        return candidate > now ? candidate : nil
    }

    private var allNotificationIdentifiers: [String] {
        let calendar = Calendar.current
        let now = Date()
        let wellnessIdentifiers = (0..<7).flatMap { dayOffset -> [String] in
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { return [] }
            let sanitizedHours = AppSettings.sanitizeWellnessWorkHours(
                startMinutes: AppSettings.wellnessBreakStartMinutes,
                endMinutes: AppSettings.wellnessBreakEndMinutes
            )
            let intervalMinutes = max(AppSettings.wellnessBreakIntervalMinutes, 1)
            var identifiers: [String] = []
            var currentMinutes = sanitizedHours.startMinutes + intervalMinutes
            while currentMinutes < sanitizedHours.endMinutes {
                if let candidateDate = date(at: currentMinutes, on: dayDate, calendar: calendar) {
                    identifiers.append(wellnessNotificationIdentifier(for: candidateDate))
                }
                currentMinutes += intervalMinutes
            }
            return identifiers
        }

        let todoIntervalMinutes = AppSettings.normalizeTodoReminderIntervalMinutes(AppSettings.todoReminderIntervalMinutes)
        let todoIdentifiers = stride(from: 11 * 60, through: 17 * 60, by: todoIntervalMinutes)
            .map { "focuseddayplanner.pending.\($0)" }

        return [testNotificationIdentifier, "focuseddayplanner.empty.11"] +
            todoIdentifiers +
            wellnessIdentifiers
    }

    private func wellnessNotificationIdentifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyyMMddHHmm"
        return "\(Self.wellnessNotificationIdentifierValue).\(formatter.string(from: date))"
    }

    private var testNotificationIdentifier: String {
        Self.testNotificationIdentifierValue
    }

    private func currentNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func pendingNotificationIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let identifiers = requests.map(\.identifier).sorted()
                continuation.resume(returning: identifiers)
            }
        }
    }

    private func debugLines(for settings: UNNotificationSettings, prefix: String) -> [String] {
        [
            "Environment: supported",
            "\(prefix) authorization: \(string(for: settings.authorizationStatus))",
            "\(prefix) alerts: \(string(for: settings.alertSetting))",
            "\(prefix) sounds: \(string(for: settings.soundSetting))",
            "\(prefix) badges: \(string(for: settings.badgeSetting))"
        ]
    }

    private func string(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "not determined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }

    private func string(for setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported:
            return "not supported"
        case .disabled:
            return "disabled"
        case .enabled:
            return "enabled"
        @unknown default:
            return "unknown"
        }
    }

    private func updateNotificationStatus(_ status: String) {
        lastNotificationStatus = status
        lastNotificationUpdatedAt = .now
    }
}

private struct ReminderScheduleState: Equatable {
    let totalTodos: Int
    let pendingTodos: Int
    let notificationsEnabled: Bool
    let todoReminderIntervalMinutes: Int
    let todoReminderMessage: String
    let emptyDayReminderMessage: String
    let wellnessBreakEnabled: Bool
    let wellnessBreakIntervalMinutes: Int
    let wellnessBreakMessage: String
    let wellnessBreakStartMinutes: Int
    let wellnessBreakEndMinutes: Int
    let ignoreWeekends: Bool
}
