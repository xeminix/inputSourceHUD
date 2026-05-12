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

    private static let placeholderPayload = HUDPayload(
        icon: nil,
        appName: "",
        languageName: "",
        detailName: "",
        message: "",
        state: .success
    )

    private let settingsStore: SettingsStore

    private var hideWorkItem: DispatchWorkItem?
    private var window: HUDWindow?
    private var hostingView: NSHostingView<HUDContentView>?
    private var lastPresentationSignature: PresentationSignature?
    private var lastPresentationDate = Date.distantPast
    private var presentationRevision = 0

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    /// 앱 시작 시 한 번 호출 — HUD 윈도우/호스팅 뷰를 미리 만들어 첫 표시 비용을 없앤다.
    /// 입력소스가 처음 바뀔 때 NSPanel 생성 + SwiftUI 첫 렌더가 한꺼번에 도는 걸 막는다.
    func prewarm() {
        _ = ensureWindow()
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
        // 입력소스 전환을 알리는 distributed notification 핸들러와 같은 런루프 틱에서
        // 윈도우 생성/표시 같은 무거운 작업을 하면 직후 키 입력 타이밍과 겹칠 수 있어
        // 한 틱 뒤로 미룬다.
        DispatchQueue.main.async { [weak self] in
            self?.show(payload: payload, preferredApplication: app, ignoreHUDEnabled: false)
        }
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

        hideWorkItem?.cancel()

        let size = HUDCanvasMetrics.size
        let screen = ScreenLocator.preferredScreen(for: preferredApplication) ?? NSScreen.main
        let frame = frameForDisplay(on: screen, size: size)
        let (panel, hosting) = ensureWindow()
        let wasVisible = panel.isVisible

        hosting.rootView = makeContentView(payload: payload)
        panel.setFrame(frame, display: true)

        if wasVisible {
            // 이미 떠 있으면(또는 페이드아웃 진행 중이면) 즉시 불투명하게 끊고 새 내용 표시.
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }

        Log.hud.info(
            "Showing HUD for \(payload.appName, privacy: .public) on \(screen?.localizedName ?? "unknown screen", privacy: .public) at \(NSStringFromRect(frame), privacy: .public)"
        )

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
        guard revision == presentationRevision, let window, window.isVisible else {
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
                // 윈도우는 닫지 않고 화면에서만 내린다 — 재사용해서 다음 표시 비용/깜빡임을 없앤다.
                window.orderOut(nil)
            }
        }
    }

    private func ensureWindow() -> (HUDWindow, NSHostingView<HUDContentView>) {
        if let window, let hostingView {
            return (window, hostingView)
        }

        let frame = frameForDisplay(on: NSScreen.main, size: HUDCanvasMetrics.size)
        let panel = HUDWindow(contentRect: frame)
        let hosting = NSHostingView(rootView: makeContentView(payload: Self.placeholderPayload))
        panel.contentView = hosting
        panel.alphaValue = 0

        window = panel
        hostingView = hosting
        return (panel, hosting)
    }

    private func makeContentView(payload: HUDPayload) -> HUDContentView {
        HUDContentView(
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
