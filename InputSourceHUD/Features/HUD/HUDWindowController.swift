import AppKit
import SwiftUI

@MainActor
final class HUDWindowController {
    private struct PresentationSignature: Equatable {
        let appName: String
        let languageName: String
        let detailName: String
        let message: String
        let state: HUDState
    }

    private let settingsStore: SettingsStore

    private var hideWorkItem: DispatchWorkItem?
    private var window: HUDWindow?
    private var lastPresentationSignature: PresentationSignature?
    private var lastPresentationDate = Date.distantPast
    private var presentationRevision = 0

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func showSuccess(app: NSRunningApplication, inputSource: InputSource) {
        let payload = HUDPayload(
            icon: app.icon,
            appName: app.localizedName ?? "InputSourceHUD",
            languageName: inputSource.hudLanguageName,
            detailName: inputSource.hudDetailName,
            message: "\(app.localizedName ?? "Current App")에서 \(inputSource.hudLanguageName)로 변경됨",
            state: .success
        )
        show(payload: payload, preferredApplication: app, ignoreHUDEnabled: false)
    }

    func showMatched(app: NSRunningApplication, inputSource: InputSource) {
        guard settingsStore.settings.hud.showWhenAlreadyMatched else {
            return
        }

        let payload = HUDPayload(
            icon: app.icon,
            appName: app.localizedName ?? "InputSourceHUD",
            languageName: inputSource.hudLanguageName,
            detailName: inputSource.hudDetailName,
            message: "이미 \(inputSource.hudLanguageName)로 준비됨",
            state: .matched
        )
        show(payload: payload, preferredApplication: app, ignoreHUDEnabled: false)
    }

    func showManualChange(app: NSRunningApplication?, inputSource: InputSource) {
        guard settingsStore.settings.hud.showOnManualInputSourceChange else {
            return
        }

        let applicationName = app?.localizedName ?? "Manual Change"
        let payload = HUDPayload(
            icon: app?.icon ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil),
            appName: applicationName,
            languageName: inputSource.hudLanguageName,
            detailName: inputSource.hudDetailName,
            message: "수동으로 \(inputSource.hudLanguageName)로 변경됨",
            state: .success
        )
        Log.inputSource.info(
            "Observed manual input source change to \(inputSource.id, privacy: .public)"
        )
        show(payload: payload, preferredApplication: app, ignoreHUDEnabled: false)
    }

    func showBlocked(app: NSRunningApplication, targetInputSource: InputSource) {
        let payload = HUDPayload(
            icon: app.icon,
            appName: app.localizedName ?? "Unknown App",
            languageName: targetInputSource.hudLanguageName,
            detailName: targetInputSource.hudDetailName,
            message: "Secure Input으로 인해 변경하지 못함",
            state: .blocked
        )
        show(payload: payload, preferredApplication: app, ignoreHUDEnabled: false)
    }

    func showPreview(inputSource: InputSource?) {
        let previewSource = inputSource ?? InputSource(
            id: "preview",
            localizedName: "Preview Input Source",
            shortLabel: "P"
        )
        let payload = HUDPayload(
            icon: NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil),
            appName: "HUD Preview",
            languageName: previewSource.hudLanguageName,
            detailName: previewSource.hudDetailName,
            message: "입력 소스 변경 미리보기",
            state: .success
        )
        show(payload: payload, preferredApplication: nil, ignoreHUDEnabled: true)
    }

    private func show(
        payload: HUDPayload,
        preferredApplication: NSRunningApplication?,
        ignoreHUDEnabled: Bool
    ) {
        guard ignoreHUDEnabled || settingsStore.settings.hud.enabled else {
            return
        }

        let signature = PresentationSignature(
            appName: payload.appName,
            languageName: payload.languageName,
            detailName: payload.detailName,
            message: payload.message,
            state: payload.state
        )

        if signature == lastPresentationSignature, Date().timeIntervalSince(lastPresentationDate) < 0.12 {
            return
        }

        lastPresentationSignature = signature
        lastPresentationDate = Date()
        presentationRevision += 1
        let revision = presentationRevision

        let size = HUDCanvasMetrics.size
        let screen = ScreenLocator.preferredScreen(for: preferredApplication) ?? NSScreen.main
        let frame = frameForDisplay(on: screen, size: size)
        let (panel, shouldAnimateEntrance) = preparedWindow(frame: frame)

        panel.contentView = NSHostingView(
            rootView: HUDContentView(
                payload: payload,
                layout: settingsStore.settings.hud.layout,
                backgroundOpacity: settingsStore.settings.hud.backgroundOpacity,
                textOpacity: settingsStore.settings.hud.textOpacity,
                backgroundColor: settingsStore.settings.hud.backgroundColor?.color,
                mainTextColor: settingsStore.settings.hud.mainTextColor?.color,
                identityTextColor: settingsStore.settings.hud.identityTextColor?.color,
                badgeTextColor: settingsStore.settings.hud.badgeTextColor?.color,
                detailTextColor: settingsStore.settings.hud.detailTextColor?.color
            )
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        Log.hud.info(
            "Showing HUD for \(payload.appName, privacy: .public) on \(screen?.localizedName ?? "unknown screen", privacy: .public) at \(NSStringFromRect(frame), privacy: .public)"
        )

        if shouldAnimateEntrance {
            panel.alphaValue = 0

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                panel.animator().alphaValue = 1
            }
        }

        scheduleHide(after: settingsStore.settings.hud.durationSeconds, revision: revision)
    }

    private func scheduleHide(after duration: Double, revision: Int) {
        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideWindow(revision: revision)
        }
        hideWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func hideWindow(revision: Int) {
        guard revision == presentationRevision, let window else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                guard revision == self.presentationRevision else {
                    return
                }
                window.orderOut(nil)
                window.close()
                self.window = nil
            }
        }
    }

    private func preparedWindow(frame: CGRect) -> (HUDWindow, Bool) {
        hideWorkItem?.cancel()

        if let existingWindow = window, existingWindow.isVisible {
            return (existingWindow, false)
        }

        if let existingWindow = window {
            existingWindow.orderOut(nil)
            existingWindow.close()
        }

        let panel = HUDWindow(contentRect: frame)
        window = panel
        return (panel, true)
    }

    private func frameForDisplay(on screen: NSScreen?, size: CGSize) -> CGRect {
        let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2)
        )
        return CGRect(origin: origin, size: size)
    }
}
