import Foundation
import UserNotifications

@MainActor
final class DailyReminderScheduler {
    static let shared = DailyReminderScheduler()

    private var didRequestAuthorization = false
    private var refreshTask: Task<Void, Never>?

    private init() {}

    func refresh(totalTodos: Int, pendingTodos: Int, now: Date = .now) {
        guard Self.isSupportedEnvironment else { return }
        guard AppSettings.notificationsEnabled else {
            clearPendingNotifications()
            return
        }
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

        if totalTodos == 0 {
            if let date = nextDate(hour: 11, now: now) {
                await addNotification(
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
            await addNotification(
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

    private func addNotification(id: String, date: Date, body: String) async {
        guard let center = notificationCenter() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Focused Day Planner"
        content.body = body
        content.sound = .default

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

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
        ["focuseddayplanner.empty.11"] + (11...17).map { "focuseddayplanner.pending.\($0)" }
    }
}
