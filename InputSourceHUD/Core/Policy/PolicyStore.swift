import AppKit
import Foundation

@MainActor
final class PolicyStore {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func rule(for bundleID: String) -> AppRule? {
        settingsStore.settings.apps.first { $0.bundleId == bundleID }
    }

    func removeRule(for bundleID: String) {
        settingsStore.settings.apps.removeAll { $0.bundleId == bundleID }
        Log.app.info("Removed rule for \(bundleID, privacy: .public)")
    }

    func upsert(rule: AppRule) {
        if let index = settingsStore.settings.apps.firstIndex(where: { $0.bundleId == rule.bundleId }) {
            settingsStore.settings.apps[index] = rule
        } else {
            settingsStore.settings.apps.append(rule)
            settingsStore.settings.apps.sort { $0.displayName < $1.displayName }
        }
    }

    func addRule(for application: NSRunningApplication) {
        guard let bundleID = application.bundleIdentifier else {
            Log.app.error("Cannot add rule for frontmost app without bundle identifier")
            return
        }

        createRuleIfNeeded(
            bundleID: bundleID,
            displayName: application.localizedName ?? bundleID
        )
    }

    func addRule(forApplicationURL url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            Log.app.error("Cannot add rule for app bundle at \(url.path, privacy: .public)")
            return
        }

        let displayName =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String) ??
            FileManager.default.displayName(atPath: url.path)

        createRuleIfNeeded(
            bundleID: bundleID,
            displayName: displayName.isEmpty ? bundleID : displayName
        )
    }

    func addRule(bundleID: String, displayName: String) {
        createRuleIfNeeded(
            bundleID: bundleID,
            displayName: displayName
        )
    }

    func upsertForceRule(bundleID: String, displayName: String, inputSourceId: String) {
        let rule = AppRule(
            bundleId: bundleID,
            displayName: displayName,
            policy: .force,
            inputSourceId: inputSourceId
        )

        upsert(rule: rule)
        Log.app.info(
            "Upserted force rule for \(bundleID, privacy: .public) with input source \(inputSourceId, privacy: .public)"
        )
    }

    private func createRuleIfNeeded(bundleID: String, displayName: String) {
        guard rule(for: bundleID) == nil else {
            Log.app.debug("Rule already exists for \(bundleID, privacy: .public)")
            return
        }

        let defaultInputSourceId = settingsStore.settings.global.defaultInputSourceId
        let rule = AppRule(
            bundleId: bundleID,
            displayName: displayName,
            policy: defaultInputSourceId == nil ? .useGlobalDefault : .force,
            inputSourceId: defaultInputSourceId
        )
        upsert(rule: rule)
        Log.app.info("Added rule for \(bundleID, privacy: .public)")
    }
}
