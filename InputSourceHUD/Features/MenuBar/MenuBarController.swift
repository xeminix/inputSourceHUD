import AppKit
import Combine
import Foundation

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let settingsStore: SettingsStore
    private let policyStore: PolicyStore
    private let inputSourceChangeObserver: InputSourceChangeObserver
    private let inputSourceManager: InputSourceManager
    private let iconRenderer = MenuBarIconRenderer()

    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    var openSettingsHandler: (() -> Void)?
    var checkForUpdatesHandler: (() -> Void)?
    var canCheckForUpdatesProvider: (() -> Bool)?

    init(
        settingsStore: SettingsStore,
        policyStore: PolicyStore,
        inputSourceChangeObserver: InputSourceChangeObserver,
        inputSourceManager: InputSourceManager
    ) {
        self.settingsStore = settingsStore
        self.policyStore = policyStore
        self.inputSourceChangeObserver = inputSourceChangeObserver
        self.inputSourceManager = inputSourceManager
        super.init()
    }

    func install() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        item.button?.toolTip = "InputSourceHUD"
        statusItem = item

        rebuildMenu()
        updateStatusItemTitle()
        bind()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateCheckForUpdatesItem(in: menu)
        updateAddRuleItem(in: menu)
    }

    private func bind() {
        settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateToggleItemTitle()
            }
            .store(in: &cancellables)

        inputSourceChangeObserver.$currentInputSource
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let settingsItem = NSMenuItem(
            title: "Open Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        updatesItem.tag = 101
        menu.addItem(updatesItem)

        let addRuleItem = NSMenuItem(title: "Add Rule for Current App", action: nil, keyEquivalent: "")
        addRuleItem.tag = 102
        menu.addItem(addRuleItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem?.menu = menu
        updateToggleItemTitle()
    }

    private func updateAddRuleItem(in menu: NSMenu) {
        guard let addRuleItem = menu.item(withTag: 102) else {
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else {
            addRuleItem.title = "Add Rule for Current App"
            addRuleItem.submenu = nil
            addRuleItem.isEnabled = false
            return
        }

        let appName = app.localizedName ?? bundleID
        let existingRule = policyStore.rule(for: bundleID)
        addRuleItem.title = existingRule != nil ? "\(appName)" : "Add Rule for \(appName)"
        addRuleItem.isEnabled = true

        let submenu = NSMenu()
        for source in inputSourceManager.availableInputSources() {
            let sourceItem = NSMenuItem(
                title: "\(source.hudLanguageName) (\(source.hudDetailName))",
                action: #selector(addRuleWithInputSource(_:)),
                keyEquivalent: ""
            )
            sourceItem.target = self
            sourceItem.representedObject = (app, source)
            if existingRule?.policy == .force, existingRule?.inputSourceId == source.id {
                sourceItem.state = .on
            }
            submenu.addItem(sourceItem)
        }

        submenu.addItem(.separator())

        let defaultItem = NSMenuItem(
            title: "Use Default",
            action: #selector(setRuleToDefault(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.representedObject = app
        if existingRule?.policy == .useGlobalDefault {
            defaultItem.state = .on
        }
        submenu.addItem(defaultItem)

        let ignoreItem = NSMenuItem(
            title: "Ignore",
            action: #selector(setRuleToIgnore(_:)),
            keyEquivalent: ""
        )
        ignoreItem.target = self
        ignoreItem.representedObject = app
        if existingRule?.policy == .ignore {
            ignoreItem.state = .on
        }
        submenu.addItem(ignoreItem)

        if existingRule != nil {
            let removeItem = NSMenuItem(
                title: "Remove Rule",
                action: #selector(removeRule(_:)),
                keyEquivalent: ""
            )
            removeItem.target = self
            removeItem.representedObject = app
            submenu.addItem(removeItem)
        }

        addRuleItem.submenu = submenu
    }

    private func updateCheckForUpdatesItem(in menu: NSMenu) {
        guard let updatesItem = menu.item(withTag: 101) else {
            return
        }

        updatesItem.isEnabled = canCheckForUpdatesProvider?() ?? false
    }

    private func updateStatusItemTitle() {
        statusItem?.button?.title = iconRenderer.title(
            for: inputSourceChangeObserver.currentInputSource
        )
    }

    private func updateToggleItemTitle() {
        guard let toggleItem = statusItem?.menu?.items.first else {
            return
        }

        toggleItem.title = settingsStore.settings.global.enabled ? "Disable" : "Enable"
    }

    @objc
    private func toggleEnabled() {
        settingsStore.settings.global.enabled.toggle()
    }

    @objc
    private func openSettings() {
        openSettingsHandler?()
    }

    @objc
    private func checkForUpdates() {
        checkForUpdatesHandler?()
    }

    @objc
    private func addRuleWithInputSource(_ sender: NSMenuItem) {
        guard let (app, source) = sender.representedObject as? (NSRunningApplication, InputSource),
              let bundleID = app.bundleIdentifier
        else {
            return
        }

        policyStore.upsertForceRule(
            bundleID: bundleID,
            displayName: app.localizedName ?? bundleID,
            inputSourceId: source.id
        )
    }

    @objc
    private func setRuleToDefault(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication,
              let bundleID = app.bundleIdentifier
        else {
            return
        }
        let rule = AppRule(
            bundleId: bundleID,
            displayName: app.localizedName ?? bundleID,
            policy: .useGlobalDefault,
            inputSourceId: nil
        )
        policyStore.upsert(rule: rule)
    }

    @objc
    private func setRuleToIgnore(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication,
              let bundleID = app.bundleIdentifier
        else {
            return
        }
        // 일관성: AppsTab의 toggleIgnoreRule과 같은 토글 동작 — 이미 ignore면 rule 제거,
        // 아니면 ignore로 upsert. 체크표시(.on)를 누르면 꺼지는 자연스러운 UX.
        if policyStore.rule(for: bundleID)?.policy == .ignore {
            policyStore.removeRule(for: bundleID)
        } else {
            policyStore.upsertIgnoreRule(
                bundleID: bundleID,
                displayName: app.localizedName ?? bundleID
            )
        }
    }

    @objc
    private func removeRule(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication,
              let bundleID = app.bundleIdentifier
        else {
            return
        }
        policyStore.removeRule(for: bundleID)
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}
