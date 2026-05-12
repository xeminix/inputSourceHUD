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

    // 무한루프 방지: 재강제 시도 횟수 추적
    private struct ReEnforceAttempt {
        let bundleID: String
        let targetInputSourceID: String
        var count: Int
        let windowStart: Date
    }

    private static let reEnforceMaxAttempts = 3
    private static let reEnforceWindowSeconds: TimeInterval = 2.0
    // Per-app cooldown to suppress rapid enforce ping-pong (e.g. Safari tab
    // switches where macOS briefly flips the input source and reverts it).
    private static let reEnforceCooldownSeconds: TimeInterval = 2.5

    private var reEnforceAttempt: ReEnforceAttempt?
    private var lastEnforceTimeByBundle: [String: Date] = [:]

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

    /// 비프로그래밍적 입력소스 변경이 감지됐을 때, force 정책 앱이면 목표 입력소스로 다시 강제한다.
    /// - Returns: 재강제를 시도했으면 true, skip됐으면 false
    @discardableResult
    func enforceActivePolicyIfNeeded(
        for application: NSRunningApplication,
        currentInputSource: InputSource
    ) -> Bool {
        guard settingsStore.settings.global.enabled else {
            Log.app.debug("enforceActivePolicyIfNeeded: switching is disabled, skip")
            return false
        }

        guard let bundleID = application.bundleIdentifier else {
            Log.app.error("enforceActivePolicyIfNeeded: app missing bundle identifier")
            return false
        }

        // force 정책인 경우에만 재강제
        guard
            let rule = policyStore.rule(for: bundleID),
            rule.policy == .force,
            let targetInputSourceID = rule.inputSourceId
        else {
            Log.app.debug(
                "enforceActivePolicyIfNeeded: no force policy for \(bundleID, privacy: .public), skip"
            )
            return false
        }

        // 이미 목표 입력소스면 재강제 불필요
        guard currentInputSource.id != targetInputSourceID else {
            Log.app.debug(
                "enforceActivePolicyIfNeeded: already on target \(targetInputSourceID, privacy: .public) for \(bundleID, privacy: .public), skip"
            )
            return false
        }

        let now = Date()

        // Cooldown: 직전 재강제 후 짧은 시간 안의 반복 트리거는 무시 (Safari 탭 전환 핑퐁 억제)
        if let lastEnforce = lastEnforceTimeByBundle[bundleID],
           now.timeIntervalSince(lastEnforce) < Self.reEnforceCooldownSeconds
        {
            Log.app.debug(
                "enforceActivePolicyIfNeeded: within cooldown for \(bundleID, privacy: .public), skip"
            )
            return false
        }

        // 무한루프 방지: 같은 앱+목표 조합으로 시간 창 내 최대 횟수 초과 시 중단
        if var attempt = reEnforceAttempt,
           attempt.bundleID == bundleID,
           attempt.targetInputSourceID == targetInputSourceID,
           now.timeIntervalSince(attempt.windowStart) <= Self.reEnforceWindowSeconds
        {
            attempt.count += 1
            reEnforceAttempt = attempt

            if attempt.count > Self.reEnforceMaxAttempts {
                Log.app.warning(
                    "enforceActivePolicyIfNeeded: max re-enforce attempts (\(Self.reEnforceMaxAttempts)) reached for \(bundleID, privacy: .public), aborting to prevent loop"
                )
                return false
            }
        } else {
            // 새 시간 창 시작
            reEnforceAttempt = ReEnforceAttempt(
                bundleID: bundleID,
                targetInputSourceID: targetInputSourceID,
                count: 1,
                windowStart: now
            )
        }

        guard inputSourceManager.availableInputSources().contains(where: { $0.id == targetInputSourceID }) else {
            Log.app.error(
                "enforceActivePolicyIfNeeded: target input source \(targetInputSourceID, privacy: .public) not found for \(bundleID, privacy: .public)"
            )
            return false
        }

        if secureInputDetector.isEnabled() {
            Log.app.notice(
                "enforceActivePolicyIfNeeded: Secure Input active, cannot re-enforce for \(bundleID, privacy: .public)"
            )
            return false
        }

        let attemptNumber = reEnforceAttempt?.count ?? 1
        Log.app.info(
            "enforceActivePolicyIfNeeded: re-enforcing \(bundleID, privacy: .public) → \(targetInputSourceID, privacy: .public) (attempt \(attemptNumber)/\(Self.reEnforceMaxAttempts))"
        )

        inputSourceChangeObserver.markExpectedProgrammaticChange(to: targetInputSourceID)

        if inputSourceManager.switchToInputSource(id: targetInputSourceID) {
            inputSourceChangeObserver.refresh()
            lastEnforceTimeByBundle[bundleID] = Date()
            // No HUD here — this is a silent background correction, not a
            // user-initiated switch. Showing a HUD every time would flicker
            // (see Safari tab-switch ping-pong).
            Log.app.info(
                "enforceActivePolicyIfNeeded: succeeded for \(bundleID, privacy: .public)"
            )
            return true
        }

        inputSourceChangeObserver.clearExpectedProgrammaticChange()
        Log.inputSource.error(
            "enforceActivePolicyIfNeeded: failed to switch for \(bundleID, privacy: .public)"
        )
        return false
    }
}
