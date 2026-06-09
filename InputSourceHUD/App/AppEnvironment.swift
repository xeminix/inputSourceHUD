import AppKit
import ApplicationServices
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers
#if canImport(Sparkle)
import Sparkle
#endif

struct AppSelectionItem: Identifiable {
    let bundleID: String
    let displayName: String
    let bundleURL: URL?
    let icon: NSImage?
    let isFrontmost: Bool

    var id: String { bundleID }
    var subtitle: String { bundleID }
}

@MainActor
final class AppEnvironment: ObservableObject {
    private struct PendingPredictedManualChange {
        let inputSourceID: String
        let expiresAt: Date
    }

    @Published private(set) var recentApplications: [AppSelectionItem] = []
    @Published private(set) var runningApplications: [AppSelectionItem] = []

    let settingsStore: SettingsStore
    let inputSourceManager: InputSourceManager
    let inputSourceChangeObserver: InputSourceChangeObserver
    let inputSourceCyclePredictionMonitor: InputSourceCyclePredictionMonitor
    let secureInputDetector: SecureInputDetector
    let policyStore: PolicyStore
    let hudWindowController: HUDWindowController
    let appSwitchCoordinator: AppSwitchCoordinator
    let appSwitchObserver: AppSwitchObserver
    let menuBarController: MenuBarController
    let launchAtLoginManager: LaunchAtLoginManager
    let updateController: UpdateController
    lazy var settingsWindowController = SettingsWindowController(appEnvironment: self)

    private var cancellables = Set<AnyCancellable>()
    private var pendingPredictedManualChange: PendingPredictedManualChange?

    init() {
        settingsStore = SettingsStore()
        inputSourceManager = InputSourceManager()
        inputSourceChangeObserver = InputSourceChangeObserver(inputSourceManager: inputSourceManager)
        inputSourceCyclePredictionMonitor = InputSourceCyclePredictionMonitor(
            inputSourceManager: inputSourceManager
        )
        secureInputDetector = SecureInputDetector()
        policyStore = PolicyStore(settingsStore: settingsStore)
        hudWindowController = HUDWindowController(settingsStore: settingsStore)
        appSwitchCoordinator = AppSwitchCoordinator(
            settingsStore: settingsStore,
            policyStore: policyStore,
            inputSourceManager: inputSourceManager,
            inputSourceChangeObserver: inputSourceChangeObserver,
            secureInputDetector: secureInputDetector,
            hudWindowController: hudWindowController
        )
        appSwitchObserver = AppSwitchObserver()
        launchAtLoginManager = LaunchAtLoginManager()
        updateController = UpdateController()
        menuBarController = MenuBarController(
            settingsStore: settingsStore,
            policyStore: policyStore,
            inputSourceChangeObserver: inputSourceChangeObserver,
            inputSourceManager: inputSourceManager
        )

        appSwitchObserver.delegate = appSwitchCoordinator
        appSwitchObserver.activationHandler = { [weak self] application in
            self?.recordObservedApplication(application)
        }
        inputSourceChangeObserver.changeHandler = { [weak self] inputSource, isProgrammatic in
            self?.handleObservedInputSourceChange(inputSource, isProgrammatic: isProgrammatic)
        }
        inputSourceCyclePredictionMonitor.predictionHandler = { [weak self] inputSource in
            self?.handlePredictedInputSourceCycle(inputSource)
        }
        menuBarController.openSettingsHandler = { [weak self] in
            self?.showSettingsWindow()
        }
        menuBarController.checkForUpdatesHandler = { [weak self] in
            self?.updateController.checkForUpdates()
        }
        menuBarController.canCheckForUpdatesProvider = { [weak self] in
            self?.updateController.canPresentCheckForUpdates ?? false
        }
        bindSettings()
    }

    func start() {
        normalizeSettings()
        inputSourceChangeObserver.start()
        syncLiveInputSourceCyclePreview(promptIfNeeded: false)
        updateController.startIfConfigured()
        menuBarController.install()
        appSwitchObserver.start()
        refreshApplicationCatalogs()
        synchronizeLaunchAtLoginSetting()
        hudWindowController.prewarm()
        Log.app.info("App environment started")
    }

    func availableInputSources() -> [InputSource] {
        inputSourceManager.availableInputSources()
    }

    func addRuleForFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return
        }

        policyStore.addRule(for: application)
        refreshApplicationCatalogs()
    }

    func addRuleFromApplicationPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.message = "Select an app bundle to add a switching rule."
        panel.prompt = "Add Rule"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL =
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first ??
            URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        policyStore.addRule(forApplicationURL: url)
        refreshApplicationCatalogs()
    }

    func addRule(for item: AppSelectionItem) {
        if let bundleURL = item.bundleURL {
            policyStore.addRule(forApplicationURL: bundleURL)
        } else {
            policyStore.addRule(bundleID: item.bundleID, displayName: item.displayName)
        }

        refreshApplicationCatalogs()
    }

    func hasRule(for bundleID: String) -> Bool {
        policyStore.rule(for: bundleID) != nil
    }

    func rule(for bundleID: String) -> AppRule? {
        policyStore.rule(for: bundleID)
    }

    func assignRule(for item: AppSelectionItem, inputSourceID: String) {
        policyStore.upsertForceRule(
            bundleID: item.bundleID,
            displayName: item.displayName,
            inputSourceId: inputSourceID
        )
        refreshApplicationCatalogs()
    }

    func toggleRule(for item: AppSelectionItem, inputSourceID: String) {
        let existing = policyStore.rule(for: item.bundleID)
        if existing?.policy == .force, existing?.inputSourceId == inputSourceID {
            policyStore.removeRule(for: item.bundleID)
        } else {
            policyStore.upsertForceRule(
                bundleID: item.bundleID,
                displayName: item.displayName,
                inputSourceId: inputSourceID
            )
        }
        refreshApplicationCatalogs()
    }

    func toggleIgnoreRule(for item: AppSelectionItem) {
        let existing = policyStore.rule(for: item.bundleID)
        if existing?.policy == .ignore {
            policyStore.removeRule(for: item.bundleID)
        } else {
            policyStore.upsertIgnoreRule(
                bundleID: item.bundleID,
                displayName: item.displayName
            )
        }
        refreshApplicationCatalogs()
    }

    func defaultRuleInputSource() -> InputSource? {
        guard let inputSourceID = settingsStore.settings.global.defaultInputSourceId else {
            return nil
        }

        return availableInputSources().first { $0.id == inputSourceID }
    }

    func refreshApplicationCatalogs() {
        let workspace = NSWorkspace.shared
        let observedApplications = workspace.runningApplications.filter(shouldIncludeApplication(_:))
        let builtItems = buildAppSelectionItems(from: observedApplications)

        runningApplications = builtItems.sorted { lhs, rhs in
            if lhs.isFrontmost != rhs.isFrontmost {
                return lhs.isFrontmost
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        if let frontmostApplication = workspace.frontmostApplication, shouldIncludeApplication(frontmostApplication) {
            upsertRecentApplication(from: frontmostApplication)
        }
    }

    func previewHUD() {
        hudWindowController.showPreview(
            inputSource: inputSourceChangeObserver.currentInputSource ?? availableInputSources().first
        )
    }

    func showSettingsWindow() {
        settingsWindowController.show()
    }

    var launchAtLoginStatusDescription: String {
        switch launchAtLoginManager.currentStatus() {
        case .enabled:
            "Enabled"
        case .notRegistered:
            "Disabled"
        case .requiresApproval:
            "Requires approval in Login Items settings"
        case .notFound:
            "App service not found"
        @unknown default:
            "Unknown"
        }
    }

    var liveInputSourceCyclePredictionStatus: InputSourceCyclePredictionStatus {
        inputSourceCyclePredictionMonitor.status
    }

    var liveInputSourceCycleShortcuts: [InputSourceCycleShortcutDescriptor] {
        inputSourceCyclePredictionMonitor.configuredShortcuts
    }

    var liveInputSourceCycleShortcutSummary: String {
        inputSourceCyclePredictionMonitor.shortcutSummary()
    }

    func refreshLiveInputSourceCyclePreview(promptIfNeeded: Bool) {
        syncLiveInputSourceCyclePreview(promptIfNeeded: promptIfNeeded)
    }

    func openAccessibilitySettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func bindSettings() {
        settingsStore.$settings
            .map(\.global.launchAtLogin)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isEnabled in
                self?.applyLaunchAtLoginSetting(isEnabled)
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map(\.global.liveInputSourceCyclePreviewEnabled)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncLiveInputSourceCyclePreview(promptIfNeeded: false)
            }
            .store(in: &cancellables)
    }

    private func synchronizeLaunchAtLoginSetting() {
        let currentStatus = launchAtLoginManager.currentStatus()
        let isEnabled = currentStatus == .enabled || currentStatus == .requiresApproval

        if settingsStore.settings.global.launchAtLogin != isEnabled {
            settingsStore.settings.global.launchAtLogin = isEnabled
        }
    }

    private func applyLaunchAtLoginSetting(_ isEnabled: Bool) {
        guard launchAtLoginManager.setEnabled(isEnabled) else {
            synchronizeLaunchAtLoginSetting()
            return
        }

        if launchAtLoginManager.currentStatus() == .requiresApproval {
            Log.app.notice("Launch at login requires approval in System Settings")
        }
    }

    private func handleObservedInputSourceChange(
        _ inputSource: InputSource,
        isProgrammatic: Bool
    ) {
        inputSourceCyclePredictionMonitor.resetCycleSession()

        guard !isProgrammatic else {
            return
        }

        if consumePredictedManualChangeIfNeeded(matching: inputSource.id) {
            Log.inputSource.debug(
                "Suppressed duplicate committed input source change for predicted cycle \(inputSource.id, privacy: .public)"
            )
            return
        }

        // AX focused app catches nonactivating panel apps (Raycast, Spotlight,
        // Alfred) that don't appear in frontmostApplication / menuBarOwning.
        let workspace = NSWorkspace.shared
        let activeApplication =
            axFocusedApplication() ??
            workspace.menuBarOwningApplication ??
            workspace.frontmostApplication
        let hudApplication =
            activeApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil
            : activeApplication

        // force 정책 앱이고 앱 활성화 직후 자동 전환 윈도우 안의 변경 처리.
        if let targetApp = hudApplication,
           let bundleID = targetApp.bundleIdentifier,
           let rule = policyStore.rule(for: bundleID),
           rule.policy == .force,
           let forceTargetID = rule.inputSourceId,
           appSwitchCoordinator.isWithinAutoSwitchWindow(for: bundleID)
        {
            if inputSource.id == forceTargetID {
                // 시스템이 자동으로 target 입력소스로 복원(macOS의 앱별 입력기 기억) →
                // 사용자에게 정책이 적용됐음을 알리는 success HUD 표시.
                Log.inputSource.debug(
                    "Auto-restored to target for force-policy app \(bundleID, privacy: .public): \(inputSource.id, privacy: .public)"
                )
                hudWindowController.showSuccess(app: targetApp, inputSource: inputSource)
            } else {
                // target이 아닌 입력소스로 변경됨 (macOS의 "이전 언어 기억") → 무시하고
                // enforce. 성공 시 manual HUD 안 띄움 (깜빡임 방지).
                // 실패(maxAttempts 초과 / Secure Input / switch 실패) 시엔 사용자가 입력소스
                // 불일치를 인지할 수 있도록 manual HUD를 fallback으로 표시.
                let enforced = appSwitchCoordinator.enforceActivePolicyIfNeeded(
                    for: targetApp,
                    currentInputSource: inputSource
                )
                if enforced {
                    Log.inputSource.debug(
                        "Suppressing manual HUD for force-policy app \(bundleID, privacy: .public) (enforce succeeded within auto-switch window)"
                    )
                } else {
                    Log.inputSource.notice(
                        "Force enforce failed for \(bundleID, privacy: .public); showing manual HUD as fallback"
                    )
                    hudWindowController.showManualChange(app: targetApp, inputSource: inputSource)
                }
            }
            return
        }

        hudWindowController.showManualChange(app: hudApplication, inputSource: inputSource)
    }

    private func axFocusedApplication() -> NSRunningApplication? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        // Cap the IPC wait so a hung/busy target app can't stall the main thread.
        AXUIElementSetMessagingTimeout(systemWide, 0.1)
        var focusedAppRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )

        guard result == .success, let appElement = focusedAppRef else {
            return nil
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(appElement as! AXUIElement, &pid) == .success else {
            return nil
        }

        return NSRunningApplication(processIdentifier: pid)
    }

    private func handlePredictedInputSourceCycle(_ inputSource: InputSource) {
        pendingPredictedManualChange = PendingPredictedManualChange(
            inputSourceID: inputSource.id,
            expiresAt: Date().addingTimeInterval(4.0)
        )

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let hudApplication =
            frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil
            : frontmostApplication

        Log.inputSource.debug(
            "Predicted input source cycle to \(inputSource.id, privacy: .public)"
        )
        hudWindowController.showManualChange(app: hudApplication, inputSource: inputSource)
    }

    private func consumePredictedManualChangeIfNeeded(matching inputSourceID: String) -> Bool {
        guard let pendingPredictedManualChange else {
            return false
        }

        if pendingPredictedManualChange.expiresAt < Date() {
            self.pendingPredictedManualChange = nil
            return false
        }

        guard pendingPredictedManualChange.inputSourceID == inputSourceID else {
            self.pendingPredictedManualChange = nil
            return false
        }

        self.pendingPredictedManualChange = nil
        return true
    }

    private func syncLiveInputSourceCyclePreview(promptIfNeeded: Bool) {
        if !settingsStore.settings.global.liveInputSourceCyclePreviewEnabled {
            pendingPredictedManualChange = nil
        }

        inputSourceCyclePredictionMonitor.configure(
            isEnabled: settingsStore.settings.global.liveInputSourceCyclePreviewEnabled,
            promptIfNeeded: promptIfNeeded
        )
    }

    private func recordObservedApplication(_ application: NSRunningApplication) {
        guard shouldIncludeApplication(application) else {
            return
        }

        upsertRecentApplication(from: application)
        refreshRunningApplications(preservingRecentItemsFrom: application)
    }

    private func refreshRunningApplications(preservingRecentItemsFrom application: NSRunningApplication? = nil) {
        let builtItems = buildAppSelectionItems(
            from: NSWorkspace.shared.runningApplications.filter(shouldIncludeApplication(_:))
        )

        runningApplications = builtItems.sorted { lhs, rhs in
            if lhs.isFrontmost != rhs.isFrontmost {
                return lhs.isFrontmost
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        if let application {
            upsertRecentApplication(from: application)
        }
    }

    private func buildAppSelectionItems(from applications: [NSRunningApplication]) -> [AppSelectionItem] {
        var seenBundleIDs = Set<String>()
        var items: [AppSelectionItem] = []

        for application in applications {
            guard
                let item = makeSelectionItem(from: application),
                seenBundleIDs.insert(item.bundleID).inserted
            else {
                continue
            }

            items.append(item)
        }

        return items
    }

    private func makeSelectionItem(from application: NSRunningApplication) -> AppSelectionItem? {
        guard
            shouldIncludeApplication(application),
            let bundleID = application.bundleIdentifier
        else {
            return nil
        }

        let displayName = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (displayName?.isEmpty == false ? displayName : nil) ?? bundleID
        let bundleURL = application.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)

        return AppSelectionItem(
            bundleID: bundleID,
            displayName: resolvedName,
            bundleURL: bundleURL,
            icon: application.icon,
            isFrontmost: application.isActive
        )
    }

    private func upsertRecentApplication(from application: NSRunningApplication) {
        guard let item = makeSelectionItem(from: application) else {
            return
        }

        recentApplications.removeAll { $0.bundleID == item.bundleID }
        recentApplications.insert(item, at: 0)
        recentApplications = Array(recentApplications.prefix(8))
    }

    private func shouldIncludeApplication(_ application: NSRunningApplication) -> Bool {
        guard
            let bundleID = application.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier,
            application.activationPolicy == .regular
        else {
            return false
        }

        let displayName = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !displayName.isEmpty
    }

    private func normalizeSettings() {
        let allowedInputSources = availableInputSources()
        let allowedIDs = Set(allowedInputSources.map(\.id))

        guard let fallbackID = allowedInputSources.first?.id else {
            return
        }

        settingsStore.settings.hud.layout.normalizeUniquePositions()

        if !allowedIDs.contains(settingsStore.settings.global.defaultInputSourceId ?? "") {
            settingsStore.settings.global.defaultInputSourceId = fallbackID
            Log.app.notice("Normalized global default input source to a supported value")
        }

        for index in settingsStore.settings.apps.indices {
            guard settingsStore.settings.apps[index].policy == .force else {
                continue
            }

            if !allowedIDs.contains(settingsStore.settings.apps[index].inputSourceId ?? "") {
                settingsStore.settings.apps[index].inputSourceId = settingsStore.settings.global.defaultInputSourceId ?? fallbackID
                Log.app.notice(
                    "Normalized force input source for \(self.settingsStore.settings.apps[index].bundleId, privacy: .public)"
                )
            }
        }
    }
}

@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var isConfigured = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var configurationStatusText = "Not Configured"
    @Published private(set) var configurationHintText =
        "Set SPARKLE_APPCAST_URL and SPARKLE_PUBLIC_ED_KEY before release."
    @Published private(set) var lastUpdateEventText = "Idle"

    private let bundle: Bundle

#if canImport(Sparkle)
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private lazy var updaterSettings = SPUUpdaterSettings(hostBundle: bundle)
    private var cancellables = Set<AnyCancellable>()
    private var hasStartedUpdater = false
#endif

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        super.init()

        refreshConfigurationState()

#if canImport(Sparkle)
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
            .store(in: &cancellables)
#endif
    }

    var feedURLDisplayText: String {
        nonEmptyInfoValue(forKey: "SUFeedURL") ?? "Not configured"
    }

    var automaticallyChecksForUpdates: Bool {
#if canImport(Sparkle)
        updaterSettings.automaticallyChecksForUpdates
#else
        false
#endif
    }

    var automaticallyDownloadsUpdates: Bool {
#if canImport(Sparkle)
        updaterSettings.automaticallyDownloadsUpdates
#else
        false
#endif
    }

    var canPresentCheckForUpdates: Bool {
        isConfigured && canCheckForUpdates
    }

    func startIfConfigured() {
        refreshConfigurationState()

#if canImport(Sparkle)
        guard isConfigured, !hasStartedUpdater else {
            return
        }

        updaterController.startUpdater()
        hasStartedUpdater = true
#endif
    }

    func checkForUpdates() {
#if canImport(Sparkle)
        startIfConfigured()
        guard isConfigured else {
            return
        }

        lastUpdateEventText = "Checking for updates…"
        updaterController.checkForUpdates(nil)
#endif
    }

    func checkForUpdatesInBackground() {
#if canImport(Sparkle)
        startIfConfigured()
        guard isConfigured else {
            return
        }

        lastUpdateEventText = "Checking in background…"
        updaterController.updater.checkForUpdatesInBackground()
#endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
#if canImport(Sparkle)
        updaterSettings.automaticallyChecksForUpdates = enabled
        objectWillChange.send()
#endif
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
#if canImport(Sparkle)
        updaterSettings.automaticallyDownloadsUpdates = enabled
        objectWillChange.send()
#endif
    }

    private func refreshConfigurationState() {
        let feedURL = nonEmptyInfoValue(forKey: "SUFeedURL")
        let publicKey = nonEmptyInfoValue(forKey: "SUPublicEDKey")

        if feedURL == nil && publicKey == nil {
            isConfigured = false
            configurationStatusText = "Feed URL + EdDSA Key Missing"
            configurationHintText =
                "Set SPARKLE_APPCAST_URL and SPARKLE_PUBLIC_ED_KEY before shipping your first Sparkle-enabled DMG."
        } else if feedURL == nil {
            isConfigured = false
            configurationStatusText = "Feed URL Missing"
            configurationHintText =
                "Point SPARKLE_APPCAST_URL at your hosted appcast.xml before release."
        } else if publicKey == nil {
            isConfigured = false
            configurationStatusText = "EdDSA Key Missing"
            configurationHintText =
                "Generate Sparkle keys and assign the public key to SPARKLE_PUBLIC_ED_KEY before release."
        } else {
            isConfigured = true
            configurationStatusText = "Configured"
            configurationHintText =
                "Sparkle is ready to check a hosted appcast and can reuse your notarized DMG or zip archives."
        }
    }

    private func nonEmptyInfoValue(forKey key: String) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

#if canImport(Sparkle)
extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        lastUpdateEventText = "Appcast loaded"
        Log.app.info("Sparkle loaded appcast with \(appcast.items.count) items")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        lastUpdateEventText = "Update found: \(item.displayVersionString)"
        Log.app.notice(
            "Sparkle found update \(item.versionString, privacy: .public) (\(item.displayVersionString, privacy: .public))"
        )
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        lastUpdateEventText = "Installing update \(item.displayVersionString)"
        Log.app.notice(
            "Sparkle will install update \(item.versionString, privacy: .public)"
        )
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        lastUpdateEventText = "Update aborted"
        Log.app.error("Sparkle aborted update cycle: \(error.localizedDescription, privacy: .public)")
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if let error {
            lastUpdateEventText = "Update cycle failed"
            Log.app.error("Sparkle finished update cycle with error: \(error.localizedDescription, privacy: .public)")
        } else {
            lastUpdateEventText = "Update cycle finished"
            Log.app.info("Sparkle finished update cycle")
        }
    }
}
#endif
