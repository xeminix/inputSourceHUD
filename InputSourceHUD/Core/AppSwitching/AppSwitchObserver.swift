@preconcurrency import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol AppSwitchHandling: AnyObject {
    func handleActivatedApplication(_ application: NSRunningApplication)
}

@MainActor
final class AppSwitchObserver: NSObject {
    private struct ApplicationSignature: Equatable {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
    }

    weak var delegate: AppSwitchHandling?
    var activationHandler: ((NSRunningApplication) -> Void)?

    private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    private var isStarted = false
    private var pollTimer: Timer?
    private var lastDeliveredApplication: ApplicationSignature?

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        lastDeliveredApplication = signature(for: NSWorkspace.shared.frontmostApplication)
        startFrontmostApplicationPolling()

        Log.app.info("App switch observer started")
    }

    @objc
    private func handleDidActivateApplication(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else {
            return
        }

        deliverIfNeeded(application, reason: "workspaceDidActivate")
    }

    @objc
    private func handleActiveSpaceDidChange(_ notification: Notification) {
        pollFrontmostApplication(reason: "activeSpaceDidChange")
    }

    private func startFrontmostApplicationPolling() {
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollFrontmostApplication(reason: "frontmostPoll")
            }
        }

        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pollFrontmostApplication(reason: String) {
        // Resolution order: AX focused → menuBar owner → NSWorkspace frontmost.
        // Nonactivating panel apps (Raycast/Spotlight/Alfred) don't change
        // frontmostApplication or menuBarOwningApplication, but they *do*
        // become the system-wide AX-focused app when they receive keyboard
        // input. Falls back gracefully if Accessibility permission is missing.
        let workspace = NSWorkspace.shared
        let application =
            axFocusedApplication() ??
            workspace.menuBarOwningApplication ??
            workspace.frontmostApplication

        guard let application else {
            return
        }

        deliverIfNeeded(application, reason: reason)
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

    private func deliverIfNeeded(_ application: NSRunningApplication, reason: String) {
        let currentSignature = signature(for: application)

        guard currentSignature != lastDeliveredApplication else {
            return
        }

        lastDeliveredApplication = currentSignature

        Log.app.info(
            "Observed app activation via \(reason, privacy: .public): \(application.localizedName ?? "Unknown App", privacy: .public) (\(application.bundleIdentifier ?? "missing-bundle-id", privacy: .public))"
        )

        activationHandler?(application)
        delegate?.handleActivatedApplication(application)
    }

    private func signature(for application: NSRunningApplication?) -> ApplicationSignature? {
        guard let application else {
            return nil
        }

        return ApplicationSignature(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier
        )
    }
}
