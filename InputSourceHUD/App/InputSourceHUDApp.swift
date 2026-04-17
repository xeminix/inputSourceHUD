import AppKit
import SwiftUI

@main
struct InputSourceHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsWindow()
                .environmentObject(appDelegate.environment)
                .environmentObject(appDelegate.environment.settingsStore)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.start()

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--open-settings-on-launch") {
            DispatchQueue.main.async {
                self.environment.showSettingsWindow()
            }
        }
#endif
    }
}
