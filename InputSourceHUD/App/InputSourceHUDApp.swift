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

        // 앱 시작마다 한 번 자동으로 업데이트 체크 (Sparkle 주기 체크와는 별개).
        // 사용자가 자동 업데이트를 껐으면 건너뜀. 약간 지연해서 네트워크/초기화 안정화 후 실행.
        if environment.updateController.automaticallyChecksForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.environment.updateController.checkForUpdatesInBackground()
            }
        }

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
    }
}
