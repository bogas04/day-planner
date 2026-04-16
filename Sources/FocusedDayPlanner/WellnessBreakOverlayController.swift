import AppKit
import Foundation
import SwiftUI

@MainActor
final class WellnessBreakOverlayController: ObservableObject {
    static let shared = WellnessBreakOverlayController()

    @Published private(set) var prompt: Prompt?

    private var dismissalTask: Task<Void, Never>?
    private var overlayWindow: NSWindow?
    private var overlayHostingView: NSHostingView<AnyView>?

    private init() {}

    func configure(isEnabled: Bool, intervalMinutes: Int) {
        _ = intervalMinutes
        if !isEnabled {
            dismiss()
        }
    }

    func show(title: String, message: String) {
        dismissalTask?.cancel()
        prompt = Prompt(title: title, message: message, shownAt: .now)
        AppLogger.overlay.notice("Showing wellness break overlay.")

        NSApp.activate(ignoringOtherApps: true)
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
        dismissalTask?.cancel()
        dismissalTask = nil
        prompt = nil
        AppLogger.overlay.notice("Dismissing wellness break overlay.")
        overlayHostingView?.rootView = AnyView(EmptyView())
        overlayWindow?.orderOut(nil)
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
                dismiss: { [weak self] in self?.dismiss() }
            )
        )
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
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
