import Foundation
import UserNotifications

@MainActor
final class DailyReminderScheduler {
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

    private init() {}

    func refresh(totalTodos: Int, pendingTodos: Int, now: Date = .now) {
        guard Self.isSupportedEnvironment else { return }
        guard AppSettings.notificationsEnabled else {
            WellnessBreakOverlayController.shared.configure(isEnabled: false, intervalMinutes: AppSettings.defaultWellnessBreakIntervalMinutes)
            clearPendingNotifications()
            lastScheduledState = nil
            return
        }
        let state = ReminderScheduleState(
            totalTodos: totalTodos,
            pendingTodos: pendingTodos,
            notificationsEnabled: AppSettings.notificationsEnabled,
            wellnessBreakEnabled: AppSettings.wellnessBreakRemindersEnabled,
            wellnessBreakIntervalMinutes: AppSettings.wellnessBreakIntervalMinutes
        )
        if state == lastScheduledState {
            return
        }
        lastScheduledState = state

        WellnessBreakOverlayController.shared.configure(
            isEnabled: AppSettings.wellnessBreakRemindersEnabled,
            intervalMinutes: AppSettings.wellnessBreakIntervalMinutes
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
            return DebugSnapshot(lines: lines)
        }

        let scheduled = await addNotification(
            id: testNotificationIdentifier,
            date: Date().addingTimeInterval(1),
            body: "This is a test reminder from Focused Day Planner."
        )
        lines.append("Schedule result: \(scheduled ? "queued test notification for ~1 second from now." : "failed to queue test notification.")")
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
            await addRepeatingNotification(
                id: wellnessNotificationIdentifier,
                timeInterval: TimeInterval(AppSettings.wellnessBreakIntervalMinutes * 60),
                body: "Time to stand up, stretch, or rest your eyes."
            )
        }

        if totalTodos == 0 {
            if let date = nextDate(hour: 11, now: now) {
                _ = await addNotification(
                    id: "focuseddayplanner.empty.11",
                    date: date,
                    body: "What would you like to work on today?"
                )
            }
            return
        }

        guard pendingTodos > 0 else { return }

        for hour in 11...17 {
            guard let date = nextDate(hour: hour, now: now) else { continue }
            _ = await addNotification(
                id: "focuseddayplanner.pending.\(hour)",
                date: date,
                body: "You have \(pendingTodos) todos left, let's do it!"
            )
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

    private func nextDate(hour: Int, now: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        components.second = 0

        guard let candidate = calendar.date(from: components) else { return nil }
        return candidate > now ? candidate : nil
    }

    private var allNotificationIdentifiers: [String] {
        [testNotificationIdentifier, wellnessNotificationIdentifier, "focuseddayplanner.empty.11"] + (11...17).map { "focuseddayplanner.pending.\($0)" }
    }

    private var wellnessNotificationIdentifier: String {
        Self.wellnessNotificationIdentifierValue
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
}

private struct ReminderScheduleState: Equatable {
    let totalTodos: Int
    let pendingTodos: Int
    let notificationsEnabled: Bool
    let wellnessBreakEnabled: Bool
    let wellnessBreakIntervalMinutes: Int
}
