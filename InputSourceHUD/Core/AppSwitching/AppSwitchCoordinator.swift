import AppKit
import Foundation

@MainActor
final class AppSwitchCoordinator: AppSwitchHandling {
    private let settingsStore: SettingsStore
    private let policyStore: PolicyStore
    private let inputSourceManager: InputSourceManager
    private let inputSourceChangeObserver: InputSourceChangeObserver
    private let secureInputDetector: SecureInputDetector
    private let hudWindowController: HUDWindowController

    private var pendingWorkItem: DispatchWorkItem?

    init(
        settingsStore: SettingsStore,
        policyStore: PolicyStore,
        inputSourceManager: InputSourceManager,
        inputSourceChangeObserver: InputSourceChangeObserver,
        secureInputDetector: SecureInputDetector,
        hudWindowController: HUDWindowController
    ) {
        self.settingsStore = settingsStore
        self.policyStore = policyStore
        self.inputSourceManager = inputSourceManager
        self.inputSourceChangeObserver = inputSourceChangeObserver
        self.secureInputDetector = secureInputDetector
        self.hudWindowController = hudWindowController
    }

    func handleActivatedApplication(_ application: NSRunningApplication) {
        pendingWorkItem?.cancel()

        let debounceMillis = settingsStore.settings.global.debounceMillis
        let workItem = DispatchWorkItem { [weak self] in
            self?.process(application)
        }

        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(debounceMillis),
            execute: workItem
        )
    }

    private func process(_ application: NSRunningApplication) {
        inputSourceChangeObserver.refresh()

        guard settingsStore.settings.global.enabled else {
            Log.app.debug("Ignored app activation because switching is disabled")
            return
        }

        guard let bundleID = application.bundleIdentifier else {
            Log.app.error("Activated app missing bundle identifier")
            return
        }

        Log.app.info(
            "Processing activated app \(application.localizedName ?? bundleID, privacy: .public) (\(bundleID, privacy: .public))"
        )

        guard let targetInputSource = resolveTargetInputSource(for: bundleID) else {
            Log.app.info("No target input source for \(bundleID, privacy: .public)")
            return
        }

        if inputSourceChangeObserver.currentInputSource?.id == targetInputSource.id {
            Log.app.info(
                "Skipped switch for \(bundleID, privacy: .public) because current input source already matches \(targetInputSource.id, privacy: .public)"
            )
            hudWindowController.showMatched(app: application, inputSource: targetInputSource)
            return
        }

        if secureInputDetector.isEnabled() {
            hudWindowController.showBlocked(app: application, targetInputSource: targetInputSource)
            Log.app.notice("Skipped input switch due to Secure Input")
            return
        }

        inputSourceChangeObserver.markExpectedProgrammaticChange(to: targetInputSource.id)

        if inputSourceManager.switchToInputSource(id: targetInputSource.id) {
            inputSourceChangeObserver.refresh()
            hudWindowController.showSuccess(app: application, inputSource: targetInputSource)
            return
        }

        inputSourceChangeObserver.clearExpectedProgrammaticChange()

        Log.inputSource.error(
            "Failed to switch input source for \(bundleID, privacy: .public)"
        )
    }

    private func resolveTargetInputSource(for bundleID: String) -> InputSource? {
        if let rule = policyStore.rule(for: bundleID) {
            switch rule.policy {
            case .ignore:
                Log.app.debug("Policy ignore matched for \(bundleID, privacy: .public)")
                return nil
            case .useGlobalDefault:
                Log.app.debug("Policy useGlobalDefault matched for \(bundleID, privacy: .public)")
                return globalDefaultInputSource()
            case .force:
                guard let inputSourceID = rule.inputSourceId else {
                    Log.app.error("Force policy missing input source for \(bundleID, privacy: .public)")
                    return nil
                }
                Log.app.debug(
                    "Policy force matched for \(bundleID, privacy: .public): \(inputSourceID, privacy: .public)"
                )
                return inputSourceManager.availableInputSources().first {
                    $0.id == inputSourceID
                }
            }
        }

        Log.app.debug("No app-specific rule for \(bundleID, privacy: .public); using global default")
        return globalDefaultInputSource()
    }

    private func globalDefaultInputSource() -> InputSource? {
        guard let defaultInputSourceID = settingsStore.settings.global.defaultInputSourceId else {
            Log.app.notice("No global default input source configured")
            return nil
        }

        return inputSourceManager.availableInputSources().first {
            $0.id == defaultInputSourceID
        }
    }
}
