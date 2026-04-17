import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(appEnvironment: AppEnvironment) {
        let rootView = SettingsWindow()
            .environmentObject(appEnvironment)
            .environmentObject(appEnvironment.settingsStore)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.backgroundColor = .clear
        window.contentViewController = hostingController
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("InputSourceHUD.Settings")
        window.title = "InputSourceHUD Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else {
            return
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
