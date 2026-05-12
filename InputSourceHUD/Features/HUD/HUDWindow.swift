import AppKit

final class HUDWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        animationBehavior = .utilityWindow
        backgroundColor = .clear
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces]
        hasShadow = true
        // 정보 표시 전용 오버레이 — 마우스 클릭/스크롤/드래그를 가로채지 않고 뒤 창으로 통과시킨다.
        ignoresMouseEvents = true
        isFloatingPanel = true
        isMovableByWindowBackground = false
        isOpaque = false
        level = .statusBar
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
