import AppKit
import ApplicationServices
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
    // 앱 활성화 직후 이 시간 안에 들어오는 외부 입력소스 변경만 macOS의 자동 전환
    // ("이전 언어 기억" 등)으로 간주해서 force 정책으로 되돌린다. 윈도우 밖의 변경은
    // 사용자 의도(Cmd+Space 등)로 보고 enforce하지 않는다.
    static let autoSwitchWindowSeconds: TimeInterval = 1.5
    // IME unlock toggle 재호출 방지 cooldown. 토글이 ping-pong을 유발하는 앱
    // (카카오톡 등)에서 무한 토글 루프를 막는다.
    private static let toggleCooldownSeconds: TimeInterval = 1.0

    private var reEnforceAttempt: ReEnforceAttempt?
    private var lastActivationTimeByBundle: [String: Date] = [:]
    private var lastToggleTimeByBundle: [String: Date] = [:]

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

        if let bundleID = application.bundleIdentifier {
            lastActivationTimeByBundle[bundleID] = Date()
        }
        pruneStaleTimeEntries()

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

    /// 활성화/토글 시간 사전이 bundleID별로 무한 증가하지 않도록 만료된 entry 제거.
    private func pruneStaleTimeEntries() {
        let now = Date()
        let activationCutoff = Self.autoSwitchWindowSeconds * 4
        lastActivationTimeByBundle = lastActivationTimeByBundle.filter {
            now.timeIntervalSince($0.value) <= activationCutoff
        }
        let toggleCutoff = Self.toggleCooldownSeconds * 4
        lastToggleTimeByBundle = lastToggleTimeByBundle.filter {
            now.timeIntervalSince($0.value) <= toggleCutoff
        }
    }

    /// 해당 앱이 활성화된 직후 자동 전환 윈도우 안인지 여부.
    /// AppEnvironment가 외부 변경의 출처(macOS 자동 vs 사용자 직접)를 시간으로 구분할 때 사용.
    func isWithinAutoSwitchWindow(for bundleID: String) -> Bool {
        guard let activatedAt = lastActivationTimeByBundle[bundleID] else {
            return false
        }
        return Date().timeIntervalSince(activatedAt) <= Self.autoSwitchWindowSeconds
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
            // already matches 케이스에선 토글 호출 안 함. 카카오톡 같은 앱은 정상 진입 시
            // 이미 한글이라 토글이 오히려 ABC 신호로 IME를 잠그는 부작용 가능. macOS와
            // 우리가 일치하는 경우엔 외부 시그널 발행할 필요 없음.
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
            // TIS가 noErr를 반환했지만 실제로는 입력소스가 안 바뀌는 케이스 대비 검증.
            scheduleSwitchVerification(targetID: targetInputSource.id, bundleID: bundleID, retries: 2)
            // Ghostty 등 일부 앱의 IME 컨텍스트 잠금 해제용 토글 (input method 한정).
            scheduleIMEUnlockToggle(targetID: targetInputSource.id, bundleID: bundleID)
            return
        }

        inputSourceChangeObserver.clearExpectedProgrammaticChange()

        Log.inputSource.error(
            "Failed to switch input source for \(bundleID, privacy: .public)"
        )
    }

    /// switchToInputSource 호출 직후 currentInputSource를 확인해, TIS는 성공으로 보고했지만
    /// 실제 입력소스가 안 바뀐 경우 재시도한다. 일부 앱(Ghostty 등)에서 한글 input method
    /// 활성화가 늦거나 누락되는 케이스 보호.
    private func scheduleSwitchVerification(targetID: String, bundleID: String, retries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
            guard let self else { return }

            let current = self.inputSourceManager.currentInputSource()?.id
            if current == targetID {
                return
            }

            // retries=0이면 더 이상 재시도 안 함. 마지막 시도 결과까지 검증한 뒤 로그만 남김.
            guard retries > 0 else {
                Log.inputSource.error(
                    "Switch verification failed permanently for \(bundleID, privacy: .public): target=\(targetID, privacy: .public), current=\(current ?? "nil", privacy: .public)"
                )
                return
            }

            Log.inputSource.notice(
                "Switch verification mismatch for \(bundleID, privacy: .public): target=\(targetID, privacy: .public), current=\(current ?? "nil", privacy: .public), retrying (\(retries, privacy: .public) left)"
            )

            self.inputSourceChangeObserver.markExpectedProgrammaticChange(to: targetID)
            if self.inputSourceManager.switchToInputSource(id: targetID) {
                self.inputSourceChangeObserver.refresh()
                self.scheduleSwitchVerification(
                    targetID: targetID,
                    bundleID: bundleID,
                    retries: retries - 1
                )
            } else {
                self.inputSourceChangeObserver.clearExpectedProgrammaticChange()
                Log.inputSource.error(
                    "Switch retry failed for \(bundleID, privacy: .public) → \(targetID, privacy: .public)"
                )
            }
        }
    }

    /// 일부 앱(Ghostty 등)이 TIS notification만으로는 IME 컨텍스트를 갱신 못 하는 케이스
    /// 해결용. 사용자가 직접 Cmd+Space로 한영 전환할 때처럼 CGEvent로 시스템 입력기 cycle
    /// 키를 시뮬레이트해서 macOS의 모든 IME 동기화 경로를 트리거한 뒤, TIS로 target 복원.
    /// target이 keyboard layout이면 IMK 잠금 문제가 없으므로 적용하지 않는다.
    /// Accessibility 권한 미부여 시 시뮬레이트 자체를 skip한다 (silent failure 방지).
    private func scheduleIMEUnlockToggle(targetID: String, bundleID: String) {
        guard targetID.contains("inputmethod") else {
            return
        }

        // 권한이 없으면 CGEvent.post가 silent fail하고, 그러면 토글 자체가 무의미.
        // 토글 본체에서 markExpected를 잘못 마킹하는 부작용도 함께 차단.
        guard AXIsProcessTrusted() else {
            Log.inputSource.notice(
                "Accessibility not granted; skipping IME unlock toggle for \(bundleID, privacy: .public)"
            )
            return
        }

        let now = Date()
        if let last = lastToggleTimeByBundle[bundleID],
           now.timeIntervalSince(last) < Self.toggleCooldownSeconds
        {
            Log.inputSource.debug(
                "Skipping IME unlock simulation within cooldown for \(bundleID, privacy: .public)"
            )
            return
        }
        lastToggleTimeByBundle[bundleID] = now

        // 1단계: 150ms 후 Cmd+Space 시뮬레이트 (사용자가 직접 누른 것처럼)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            guard let self else { return }

            // 토글 진행 중 사용자가 다른 앱으로 전환했으면 stale 토글이므로 abort
            // (이전 앱 target으로 복원하면 새 앱 입력소스를 잘못 덮어쓴다).
            let currentFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if let currentFrontmost, currentFrontmost != bundleID,
               currentFrontmost != Bundle.main.bundleIdentifier
            {
                Log.inputSource.debug(
                    "IME unlock aborted: frontmost changed (\(bundleID, privacy: .public) → \(currentFrontmost, privacy: .public))"
                )
                return
            }

            // burst 모드: step1/step2 사이 어떤 입력소스 변경(simulate cycle 결과, TIS 복원 등)도
            // programmatic으로 간주. 사전에 cycle 결과 ID를 정확히 알 수 없어 단일 슬롯 마킹 부정확.
            self.inputSourceChangeObserver.beginProgrammaticBurst(duration: 0.4)

            self.simulateInputSourceCycleKey()
            Log.inputSource.debug(
                "IME unlock step 1 (Cmd+Space simulate) for \(bundleID, privacy: .public)"
            )

            // 2단계: 100ms 후 TIS로 target 복원
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
                guard let self else { return }

                _ = self.inputSourceManager.switchToInputSource(id: targetID)
                self.inputSourceChangeObserver.refresh()
                Log.inputSource.debug(
                    "IME unlock step 2 (TIS restore) for \(bundleID, privacy: .public): → \(targetID, privacy: .public)"
                )

                // burst는 안전 마진(200ms 추가) 후 명시적 종료
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak self] in
                    self?.inputSourceChangeObserver.endProgrammaticBurst()
                }
            }
        }
    }

    /// CGEvent로 Cmd+Space 키 입력을 시뮬레이트. 사용자가 시스템 설정에서 한영 전환
    /// 단축키를 Cmd+Space로 등록한 경우(흔한 macOS 한글 사용자 설정)에 입력기 cycle을
    /// 트리거한다. 호출 전 Accessibility 권한 확인 필수(scheduleIMEUnlockToggle에서 이미 가드).
    private func simulateInputSourceCycleKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdKeyCode: CGKeyCode = 0x37
        let spaceKeyCode: CGKeyCode = 0x31

        // Cmd modifier 이벤트를 명시적으로 down/up 시퀀스로 발송.
        // 단순히 keyDown에 .maskCommand flag만 설정하는 방식은 일부 macOS 버전에서
        // 시스템 단축키 레이어 또는 앱별 IME 컨텍스트 갱신이 트리거되지 않는다.
        guard
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
            let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: spaceKeyCode, keyDown: true),
            let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: spaceKeyCode, keyDown: false),
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false)
        else {
            Log.inputSource.error("CGEvent creation failed")
            return
        }

        spaceDown.flags = .maskCommand
        spaceUp.flags = .maskCommand

        let tap: CGEventTapLocation = .cghidEventTap
        cmdDown.post(tap: tap)
        spaceDown.post(tap: tap)
        spaceUp.post(tap: tap)
        cmdUp.post(tap: tap)
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
            // No HUD here — this is a silent background correction, not a
            // user-initiated switch. Showing a HUD every time would flicker.
            Log.app.info(
                "enforceActivePolicyIfNeeded: succeeded for \(bundleID, privacy: .public)"
            )
            scheduleSwitchVerification(targetID: targetInputSourceID, bundleID: bundleID, retries: 2)
            // Ghostty 시나리오 4: 영어로 나갔다 돌아온 경우 macOS가 ABC로 복원하고
            // 여기서 한글로 enforce하는데, Ghostty IME 컨텍스트가 영어로 잠긴 채 남는다.
            // 토글로 IME 갱신 시그널을 다시 발행. cooldown으로 ping-pong은 차단.
            scheduleIMEUnlockToggle(targetID: targetInputSourceID, bundleID: bundleID)
            return true
        }

        inputSourceChangeObserver.clearExpectedProgrammaticChange()
        Log.inputSource.error(
            "enforceActivePolicyIfNeeded: failed to switch for \(bundleID, privacy: .public)"
        )
        return false
    }
}
