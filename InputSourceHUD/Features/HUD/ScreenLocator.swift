import AppKit
import CoreGraphics
import Foundation

struct ScreenLocator {
    static func preferredScreen(for application: NSRunningApplication?) -> NSScreen? {
        if let application, let screen = screenForApplicationWindow(of: application) {
            return screen
        }

        return currentMouseScreen()
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
