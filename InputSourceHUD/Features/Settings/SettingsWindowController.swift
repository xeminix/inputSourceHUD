import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    nonisolated(unsafe) private var keyMonitor: Any?

    init(appEnvironment: AppEnvironment) {
        let rootView = SettingsWindow()
            .environmentObject(appEnvironment)
            .environmentObject(appEnvironment.settingsStore)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.backgroundColor = .clear
        window.contentViewController = hostingController
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("InputSourceHUD.Settings")
        window.title = "InputSourceHUD Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        super.init(window: window)
        shouldCascadeWindows = false
        installKeyboardScrollMonitor()
    }

    private func installKeyboardScrollMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window == window
            else {
                return event
            }

            // 텍스트 입력 중이면 가로채지 않음
            if let firstResponder = window.firstResponder as? NSText, firstResponder.isEditable {
                return event
            }

            switch event.keyCode {
            case 116: // Page Up
                return self.performScroll(direction: .pageUp) ? nil : event
            case 121: // Page Down
                return self.performScroll(direction: .pageDown) ? nil : event
            case 115: // Home
                return self.performScroll(direction: .home) ? nil : event
            case 119: // End
                return self.performScroll(direction: .end) ? nil : event
            default:
                return event
            }
        }
    }

    private enum ScrollDirection {
        case pageUp, pageDown, home, end
    }

    @discardableResult
    private func performScroll(direction: ScrollDirection) -> Bool {
        guard
            let contentView = window?.contentView,
            let scrollView = Self.findScrollView(in: contentView)
        else {
            return false
        }

        switch direction {
        case .pageUp:
            scrollView.pageUp(nil)
        case .pageDown:
            scrollView.pageDown(nil)
        case .home:
            scrollView.documentView?.scroll(.zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        case .end:
            if let docView = scrollView.documentView {
                let maxY = max(0, docView.bounds.height - scrollView.contentView.bounds.height)
                docView.scroll(NSPoint(x: 0, y: maxY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        return true
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        // 사이드바에는 ScrollView가 없으므로 콘텐츠 영역의 첫 번째 NSScrollView를 사용.
        if let scroll = view as? NSScrollView, scroll.documentView != nil, scroll.frame.width > 200 {
            return scroll
        }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) {
                return found
            }
        }
        return nil
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else {
            return
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
