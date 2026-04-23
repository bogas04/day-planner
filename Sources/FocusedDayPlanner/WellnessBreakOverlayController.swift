import AppKit
import Foundation
import SwiftUI

@MainActor
final class WellnessBreakOverlayController: ObservableObject {
    static let shared = WellnessBreakOverlayController()

    @Published private(set) var prompt: Prompt?
    @Published private(set) var timerIsActive = false
    @Published private(set) var nextTriggerDate: Date?
    @Published private(set) var lastOverlayShownAt: Date?
    @Published private(set) var breakSessionEndDate: Date?

    private var repeatingTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?
    private var breakSessionTask: Task<Void, Never>?
    private var overlayWindow: NSWindow?
    private var overlayHostingView: NSHostingView<AnyView>?
    private var overlayMessage = AppSettings.defaultWellnessBreakMessage
    private var workdayStartMinutes = AppSettings.defaultWellnessBreakStartMinutes
    private var workdayEndMinutes = AppSettings.defaultWellnessBreakEndMinutes
    private var skipWeekends = true

    private init() {}

    func configure(
        isEnabled: Bool,
        intervalMinutes: Int,
        message: String,
        workdayStartMinutes: Int,
        workdayEndMinutes: Int,
        skipWeekends: Bool
    ) {
        repeatingTask?.cancel()
        repeatingTask = nil
        overlayMessage = AppSettings.normalizeWellnessBreakMessage(message)
        let sanitizedHours = AppSettings.sanitizeWellnessWorkHours(
            startMinutes: workdayStartMinutes,
            endMinutes: workdayEndMinutes
        )
        self.workdayStartMinutes = sanitizedHours.startMinutes
        self.workdayEndMinutes = sanitizedHours.endMinutes
        self.skipWeekends = skipWeekends

        guard isEnabled else {
            timerIsActive = false
            nextTriggerDate = nil
            dismiss()
            AppLogger.overlay.notice("Wellness overlay timer disabled.")
            return
        }

        let safeIntervalMinutes = max(intervalMinutes, 1)
        timerIsActive = true
        nextTriggerDate = nextAllowedTriggerDate(
            after: .now,
            intervalMinutes: safeIntervalMinutes
        )
        AppLogger.overlay.notice("Wellness overlay timer configured for every \(safeIntervalMinutes) minute(s).")

        repeatingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard let nextTriggerDate = self.nextAllowedTriggerDate(
                    after: .now,
                    intervalMinutes: safeIntervalMinutes
                ) else {
                    await MainActor.run {
                        self.timerIsActive = false
                        self.nextTriggerDate = nil
                    }
                    return
                }

                await MainActor.run {
                    self.nextTriggerDate = nextTriggerDate
                }

                let sleepInterval = max(nextTriggerDate.timeIntervalSinceNow, 1)
                do {
                    try await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.shouldShowBreak(at: .now) else {
                        self.nextTriggerDate = self.nextAllowedTriggerDate(
                            after: .now,
                            intervalMinutes: safeIntervalMinutes
                        )
                        return
                    }
                    self.show(
                        title: "Time for a gentle break",
                        message: self.overlayMessage
                    )
                    self.nextTriggerDate = self.nextAllowedTriggerDate(
                        after: .now,
                        intervalMinutes: safeIntervalMinutes
                    )
                }
            }
        }
    }

    func show(title: String, message: String) {
        breakSessionTask?.cancel()
        breakSessionTask = nil
        breakSessionEndDate = nil
        dismissalTask?.cancel()
        prompt = Prompt(title: title, message: message, shownAt: .now)
        lastOverlayShownAt = .now
        AppLogger.overlay.notice("Showing wellness break overlay.")

        NSApp.activate(ignoringOtherApps: true)
        playBreakChime()
        presentOverlayWindow()

        dismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 12_000_000_000)
            } catch {
                return
            }
            self?.dismiss()
        }
    }

    func dismiss() {
        breakSessionTask?.cancel()
        breakSessionTask = nil
        dismissalTask?.cancel()
        dismissalTask = nil
        prompt = nil
        breakSessionEndDate = nil
        AppLogger.overlay.notice("Dismissing wellness break overlay.")
        overlayHostingView?.rootView = AnyView(EmptyView())
        overlayWindow?.orderOut(nil)
    }

    func startBreakSession() {
        guard prompt != nil else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        breakSessionTask?.cancel()

        let endDate = Date().addingTimeInterval(120)
        breakSessionEndDate = endDate
        AppLogger.overlay.notice("Started 2-minute break session.")
        presentOverlayWindow()

        breakSessionTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000_000)
            } catch {
                return
            }
            await MainActor.run {
                self?.dismiss()
            }
        }
    }

    private func presentOverlayWindow() {
        guard let prompt else { return }

        let targetScreen = NSApp.keyWindow?.screen ?? NSScreen.main
        let frame = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let window: NSWindow
        if let existing = overlayWindow {
            window = existing
            window.setFrame(frame, display: true)
        } else {
            window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isMovable = false
            window.hidesOnDeactivate = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.animationBehavior = .none
            let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
            overlayHostingView = hostingView
            window.contentView = hostingView
            overlayWindow = window
        }

        overlayHostingView?.rootView = AnyView(
            WellnessBreakOverlayView(
                prompt: prompt,
                breakSessionEndDate: breakSessionEndDate,
                startBreakSession: { [weak self] in self?.startBreakSession() },
                dismiss: { [weak self] in self?.dismiss() }
            )
        )
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func playBreakChime() {
        let candidateNames = ["Hero", "Glass", "Ping"]
        for name in candidateNames {
            if let sound = NSSound(named: NSSound.Name(name)) {
                sound.play()
                return
            }
        }
        NSSound.beep()
    }

    private func nextAllowedTriggerDate(after date: Date, intervalMinutes: Int) -> Date? {
        let calendar = Calendar.current
        let initialCandidate = date.addingTimeInterval(TimeInterval(max(intervalMinutes, 1) * 60))
        var candidate = alignToAllowedWindow(initialCandidate, movingForwardFrom: date)
        var attempts = 0

        while attempts < 512 {
            if shouldShowBreak(at: candidate) {
                return candidate
            }
            guard let advancedCandidate = calendar.date(byAdding: .minute, value: intervalMinutes, to: candidate) else {
                return nil
            }
            candidate = alignToAllowedWindow(advancedCandidate, movingForwardFrom: candidate)
            attempts += 1
        }

        return nil
    }

    private func shouldShowBreak(at date: Date) -> Bool {
        let calendar = Calendar.current
        if skipWeekends && calendar.isDateInWeekend(date) {
            return false
        }

        let minutes = minutesSinceStartOfDay(for: date, calendar: calendar)
        return minutes >= workdayStartMinutes && minutes < workdayEndMinutes
    }

    private func alignToAllowedWindow(_ date: Date, movingForwardFrom fallbackDate: Date) -> Date {
        let calendar = Calendar.current
        var candidate = date
        var attempts = 0

        while attempts < 512 {
            if skipWeekends && calendar.isDateInWeekend(candidate) {
                candidate = nextWorkdayStart(after: candidate, calendar: calendar)
                attempts += 1
                continue
            }

            let minutes = minutesSinceStartOfDay(for: candidate, calendar: calendar)
            if minutes < workdayStartMinutes {
                return dateBySetting(minutesSinceMidnight: workdayStartMinutes, on: candidate, calendar: calendar) ?? fallbackDate
            }
            if minutes >= workdayEndMinutes {
                candidate = nextWorkdayStart(after: candidate, calendar: calendar)
                attempts += 1
                continue
            }
            return candidate
        }

        return fallbackDate
    }

    private func nextWorkdayStart(after date: Date, calendar: Calendar) -> Date {
        var day = calendar.startOfDay(for: date)
        repeat {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        } while skipWeekends && calendar.isDateInWeekend(day)

        return dateBySetting(minutesSinceMidnight: workdayStartMinutes, on: day, calendar: calendar) ?? day
    }

    private func dateBySetting(minutesSinceMidnight: Int, on date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = minutesSinceMidnight / 60
        components.minute = minutesSinceMidnight % 60
        components.second = 0
        return calendar.date(from: components)
    }

    private func minutesSinceStartOfDay(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

extension WellnessBreakOverlayController {
    struct Prompt: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
        let shownAt: Date
    }
}
