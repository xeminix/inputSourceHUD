import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    private let service = SMAppService.mainApp

    func currentStatus() -> SMAppService.Status {
        service.status
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) -> Bool {
        do {
            if isEnabled {
                try service.register()
            } else {
                try service.unregister()
            }

            Log.app.info("Launch at login set to \(isEnabled, privacy: .public)")
            return true
        } catch {
            Log.app.error("Failed to update launch at login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
