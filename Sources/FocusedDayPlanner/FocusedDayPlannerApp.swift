import AppKit
import SwiftData
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconProvider.dockIcon
    }
}

@main
struct FocusedDayPlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        do {
            return try PersistenceController.makeModelContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup(id: "main") {
            PlannerRootView()
        }
        .defaultSize(width: 1180, height: 820)
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .windowArrangement) { }
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
        .modelContainer(sharedModelContainer)
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
