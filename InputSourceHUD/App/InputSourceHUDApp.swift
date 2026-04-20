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

        if ProcessInfo.processInfo.arguments.contains("--open-settings-on-launch") {
            DispatchQueue.main.async {
                self.environment.showSettingsWindow()
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--check-for-updates-on-launch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.environment.updateController.checkForUpdates()
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--check-for-updates-in-background-on-launch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.environment.updateController.checkForUpdatesInBackground()
            }
        }
    }
}
