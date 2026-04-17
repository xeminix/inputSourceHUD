import AppKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

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
    @Published private(set) var recentApplications: [AppSelectionItem] = []
    @Published private(set) var runningApplications: [AppSelectionItem] = []

    let settingsStore: SettingsStore
    let inputSourceManager: InputSourceManager
    let inputSourceChangeObserver: InputSourceChangeObserver
    let secureInputDetector: SecureInputDetector
    let policyStore: PolicyStore
    let hudWindowController: HUDWindowController
    let appSwitchCoordinator: AppSwitchCoordinator
    let appSwitchObserver: AppSwitchObserver
    let menuBarController: MenuBarController
    let launchAtLoginManager: LaunchAtLoginManager
    lazy var settingsWindowController = SettingsWindowController(appEnvironment: self)

    private var cancellables = Set<AnyCancellable>()

    init() {
        settingsStore = SettingsStore()
        inputSourceManager = InputSourceManager()
        inputSourceChangeObserver = InputSourceChangeObserver(inputSourceManager: inputSourceManager)
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
        menuBarController.openSettingsHandler = { [weak self] in
            self?.showSettingsWindow()
        }
        bindSettings()
    }

    func start() {
        normalizeSettings()
        inputSourceChangeObserver.start()
        menuBarController.install()
        appSwitchObserver.start()
        refreshApplicationCatalogs()
        synchronizeLaunchAtLoginSetting()
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

    private func bindSettings() {
        settingsStore.$settings
            .map(\.global.launchAtLogin)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isEnabled in
                self?.applyLaunchAtLoginSetting(isEnabled)
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
        guard !isProgrammatic else {
            return
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let hudApplication =
            frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil
            : frontmostApplication

        hudWindowController.showManualChange(app: hudApplication, inputSource: inputSource)
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
