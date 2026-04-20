import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct ScreenLocator {
    // HUD가 뜰 모니터 결정 순서:
    // 1. AX API로 얻은 focused window (실제 타이핑 중인 창 — 가장 정확)
    // 2. 마우스 커서가 있는 모니터 (권한 없거나 AX 실패 시 현실적 대안)
    // 3. 앱의 가장 큰 온스크린 윈도우 (창이 여러 개일 때 heuristic)
    // 4. 메인 모니터 (최종 fallback)
    //
    // AX 호출은 메인 스레드 blocking이 수~수십 ms 발생할 수 있음.
    // 입력기 빠른 연속 전환 시 키 입력 밀림 방지 위해 PID 별 캐시(TTL) + 백그라운드 refresh.
    private static let cacheQueue = DispatchQueue(label: "com.codequa.inputSourceHUD.screenLocator")
    private static let axQueue = DispatchQueue(label: "com.codequa.inputSourceHUD.screenLocator.ax", qos: .userInitiated)
    nonisolated(unsafe) private static var focusedWindowCache: [pid_t: (screen: NSScreen, timestamp: Date)] = [:]
    nonisolated(unsafe) private static var pendingLookups: Set<pid_t> = []
    private static let cacheTTL: TimeInterval = 2.0

    static func preferredScreen(for application: NSRunningApplication?) -> NSScreen? {
        if let application, let screen = focusedWindowScreen(for: application) {
            return screen
        }

        if let screen = currentMouseScreen() {
            return screen
        }

        if let application, let screen = screenForApplicationWindow(of: application) {
            return screen
        }

        return NSScreen.main
    }

    private static func focusedWindowScreen(for application: NSRunningApplication) -> NSScreen? {
        let pid = application.processIdentifier

        // 메인 스레드 blocking 방지: 항상 캐시만 조회. 누락/만료 시 백그라운드 refresh.
        // 이번 호출은 mouse fallback으로 처리되고, 다음 호출부터는 fresh 캐시 사용.
        scheduleRefreshIfNeeded(pid: pid)

        return cacheQueue.sync {
            guard let entry = focusedWindowCache[pid] else { return nil }
            guard Date().timeIntervalSince(entry.timestamp) < cacheTTL else { return nil }
            return entry.screen
        }
    }

    private static func scheduleRefreshIfNeeded(pid: pid_t) {
        let shouldFetch: Bool = cacheQueue.sync {
            if pendingLookups.contains(pid) { return false }
            pendingLookups.insert(pid)
            return true
        }
        guard shouldFetch else { return }

        axQueue.async {
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                cacheQueue.sync { _ = pendingLookups.remove(pid) }
                return
            }
            let fresh = screenForFocusedWindow(of: app)
            cacheQueue.sync {
                if let fresh {
                    focusedWindowCache[pid] = (fresh, Date())
                }
                pendingLookups.remove(pid)
            }
        }
    }

    static func currentMouseScreen() -> NSScreen? {
        let location = CGEvent(source: nil)?.location ?? NSEvent.mouseLocation

        if let screen = screenForCurrentDisplay(at: location) {
            return screen
        }

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) {
            return screen
        }

        return nearestScreen(to: location) ?? NSScreen.main
    }

    private static func screenForFocusedWindow(of application: NSRunningApplication) -> NSScreen? {
        let axApp = AXUIElementCreateApplication(application.processIdentifier)

        var focusedRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
            let focusedRef,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let focusedWindow = focusedRef as! AXUIElement

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(focusedWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
            AXUIElementCopyAttributeValue(focusedWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let positionRef, let sizeRef
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        // AX 좌표는 top-left origin. screenForCurrentDisplay는 Quartz global(flipped) 좌표를 원하므로 그대로 사용.
        // NSScreen.frame은 bottom-left origin이라 flippedCenter로도 시도.
        let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let flippedCenter = CGPoint(x: center.x, y: flippedY(for: center.y))

        return
            screenForCurrentDisplay(at: center) ??
            screenForCurrentDisplay(at: flippedCenter) ??
            NSScreen.screens.first(where: { $0.frame.contains(flippedCenter) }) ??
            NSScreen.screens.first(where: { $0.frame.contains(center) }) ??
            nearestScreen(to: flippedCenter)
    }

    private static func screenForApplicationWindow(of application: NSRunningApplication) -> NSScreen? {
        guard let bounds = primaryWindowBounds(for: application.processIdentifier) else {
            return nil
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let flippedCenter = CGPoint(x: center.x, y: flippedY(for: center.y))

        return
            screenForCurrentDisplay(at: center) ??
            screenForCurrentDisplay(at: flippedCenter) ??
            NSScreen.screens.first(where: { $0.frame.contains(center) }) ??
            NSScreen.screens.first(where: { $0.frame.contains(flippedCenter) }) ??
            nearestScreen(to: center)
    }

    private static func primaryWindowBounds(for processIdentifier: pid_t) -> CGRect? {
        guard
            let windowInfoList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return nil
        }

        let candidateWindows = windowInfoList.compactMap { info -> CGRect? in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.int32Value == processIdentifier,
                let layer = info[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0,
                let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                bounds.width > 120,
                bounds.height > 120
            else {
                return nil
            }

            if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 {
                return nil
            }

            if let isOnscreen = info[kCGWindowIsOnscreen as String] as? NSNumber, !isOnscreen.boolValue {
                return nil
            }

            return bounds
        }

        return candidateWindows.max { lhs, rhs in
            (lhs.width * lhs.height) < (rhs.width * rhs.height)
        }
    }

    private static func screenForCurrentDisplay(at point: CGPoint) -> NSScreen? {
        var displayID = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        let result = withUnsafeMutablePointer(to: &displayID) { displayIDPointer in
            CGGetDisplaysWithPoint(point, 1, displayIDPointer, &displayCount)
        }

        guard result == .success, displayCount > 0 else {
            return nil
        }

        return screen(for: displayID)
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else {
                return false
            }

            return CGDirectDisplayID(screenNumber.uint32Value) == displayID
        }
    }

    private static func nearestScreen(to point: CGPoint) -> NSScreen? {
        NSScreen.screens.min { lhs, rhs in
            distance(from: point, to: lhs.frame) < distance(from: point, to: rhs.frame)
        }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        if rect.contains(point) {
            return 0
        }

        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return sqrt((dx * dx) + (dy * dy))
    }

    private static func flippedY(for y: CGFloat) -> CGFloat {
        let minY = NSScreen.screens.map { $0.frame.minY }.min() ?? 0
        let maxY = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        return maxY - (y - minY)
    }
}
