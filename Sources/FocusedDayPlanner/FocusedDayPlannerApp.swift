import AppKit
import SwiftData
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconProvider.dockIcon
        UNUserNotificationCenter.current().delegate = self

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.identifier == DailyReminderScheduler.testNotificationIdentifierValue ||
            notification.request.identifier == DailyReminderScheduler.wellnessNotificationIdentifierValue {
            await MainActor.run {
                WellnessBreakOverlayController.shared.show(
                    title: "Time for a gentle break",
                    message: notification.request.content.body
                )
            }
            return [.banner, .list, .badge]
        }

        return [.banner, .list, .sound, .badge]
    }
}

@main
struct FocusedDayPlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var uiScaleController = UIScaleController()
    @StateObject private var backgroundAudioController = BackgroundAudioController()
    @StateObject private var appRuntimeState = AppRuntimeState()

    var body: some Scene {
        Window("Focused Day Planner", id: "main") {
            AppContentView()
                .environmentObject(uiScaleController)
                .environmentObject(backgroundAudioController)
                .environmentObject(appRuntimeState)
        }
        .defaultSize(width: 1180, height: 820)
        .modelContainer(appRuntimeState.modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .windowArrangement) { }
            CommandMenu("Zoom") {
                Button("Zoom In") {
                    uiScaleController.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    uiScaleController.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    uiScaleController.reset()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(uiScaleController.isDefaultScale)
            }
        }

        MenuBarExtra {
            MenuBarContentView()
        } label: {
            Label {
                Text("Focused Day Planner")
            } icon: {
                Image(nsImage: AppIconProvider.menuBarIcon)
            }
        }
        .modelContainer(appRuntimeState.modelContainer)
        .environmentObject(uiScaleController)
        .environmentObject(backgroundAudioController)
        .environmentObject(appRuntimeState)
    }
}

@MainActor
final class AppRuntimeState: ObservableObject {
    let modelContainer: ModelContainer
    let startupWarning: String?

    init() {
        do {
            modelContainer = try PersistenceController.makeModelContainer()
            startupWarning = nil
            AppLogger.persistence.notice("Opened persistent model container.")
        } catch {
            do {
                modelContainer = try PersistenceController.makeInMemoryModelContainer()
                startupWarning = "The saved planner database could not be opened, so the app started with temporary in-memory storage. Error: \(error.localizedDescription)"
                AppLogger.persistence.error("Falling back to in-memory model container after persistent store failure: \(error.localizedDescription, privacy: .public)")
            } catch {
                preconditionFailure("Unable to create any model container: \(error)")
            }
        }
    }
}

private struct AppContentView: View {
    @EnvironmentObject private var appRuntimeState: AppRuntimeState
    @State private var showingStartupWarning = false

    var body: some View {
        PlannerRootView()
            .alert("Storage Recovery", isPresented: $showingStartupWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appRuntimeState.startupWarning ?? "")
            }
            .onAppear {
                if appRuntimeState.startupWarning != nil {
                    showingStartupWarning = true
                }
            }
    }
}

private struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Planner") {
            NSApp.activate(ignoringOtherApps: true)
            let existing = NSApp.windows.first {
                !$0.isMiniaturized && ($0.isVisible || $0.title.contains("Focused Day Planner"))
            }

            if let existing {
                existing.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    NSApp.windows.first { $0.title.contains("Focused Day Planner") || $0.isVisible }?
                        .makeKeyAndOrderFront(nil)
                }
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
