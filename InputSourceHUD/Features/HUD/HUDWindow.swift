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
