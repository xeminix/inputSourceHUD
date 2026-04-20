import AppKit
import ApplicationServices
import Carbon
import Combine
import Foundation

@MainActor
final class InputSourceChangeObserver: NSObject, ObservableObject {
    private struct PendingProgrammaticChange {
        let inputSourceID: String
        let expiresAt: Date
    }

    @Published private(set) var currentInputSource: InputSource?

    var changeHandler: ((InputSource, Bool) -> Void)?

    private let inputSourceManager: InputSourceManager
    private let distributedNotificationCenter = DistributedNotificationCenter.default()
    private var isStarted = false
    private var pendingProgrammaticChange: PendingProgrammaticChange?

    init(inputSourceManager: InputSourceManager) {
        self.inputSourceManager = inputSourceManager
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        distributedNotificationCenter.addObserver(
            self,
            selector: #selector(handleInputSourceDidChange),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        refresh()
        Log.inputSource.info("Input source observer started")
    }

    func refresh() {
        currentInputSource = inputSourceManager.currentInputSource()
    }

    func markExpectedProgrammaticChange(to inputSourceID: String) {
        pendingProgrammaticChange = PendingProgrammaticChange(
            inputSourceID: inputSourceID,
            expiresAt: Date().addingTimeInterval(1.2)
        )
    }

    func clearExpectedProgrammaticChange() {
        pendingProgrammaticChange = nil
    }

    @objc
    private func handleInputSourceDidChange() {
        let previousInputSourceID = currentInputSource?.id
        refresh()

        guard
            let currentInputSource,
            currentInputSource.id != previousInputSourceID
        else {
            return
        }

        let isProgrammatic = consumeProgrammaticChangeIfNeeded(matching: currentInputSource.id)
        changeHandler?(currentInputSource, isProgrammatic)
    }

    private func consumeProgrammaticChangeIfNeeded(matching inputSourceID: String) -> Bool {
        guard let pendingProgrammaticChange else {
            return false
        }

        if pendingProgrammaticChange.expiresAt < Date() {
            self.pendingProgrammaticChange = nil
            return false
        }

        guard pendingProgrammaticChange.inputSourceID == inputSourceID else {
            self.pendingProgrammaticChange = nil
            return false
        }

        self.pendingProgrammaticChange = nil
        return true
    }
}

enum InputSourceCyclePredictionStatus: Equatable {
    case disabled
    case unavailableNoShortcuts
    case requiresAccessibility
    case active
}

struct InputSourceCycleShortcutDescriptor: Identifiable, Hashable {
    let title: String
    let directionTitle: String

    var id: String {
        "\(title)-\(directionTitle)"
    }

    var displayLabel: String {
        "\(title) · \(directionTitle)"
    }
}

@MainActor
final class InputSourceCyclePredictionMonitor: ObservableObject {
    private enum Direction {
        case next
        case previous
    }

    private struct Shortcut: Equatable {
        let keyCode: Int64
        let modifiers: NSEvent.ModifierFlags
        let direction: Direction
    }

    var predictionHandler: ((InputSource) -> Void)?

    @Published private(set) var status: InputSourceCyclePredictionStatus = .disabled
    @Published private(set) var configuredShortcuts: [InputSourceCycleShortcutDescriptor] = []

    private let inputSourceManager: InputSourceManager
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeShortcut: Shortcut?
    private var shadowInputSourceID: String?
    private var shortcuts: [Shortcut] = []
    private var isStarted = false

    init(inputSourceManager: InputSourceManager) {
        self.inputSourceManager = inputSourceManager
    }

    func configure(isEnabled: Bool, promptIfNeeded: Bool) {
        reloadConfiguredShortcuts()

        guard isEnabled else {
            stop()
            status = .disabled
            return
        }

        guard !shortcuts.isEmpty else {
            stop()
            status = .unavailableNoShortcuts
            Log.inputSource.notice("No configured input-source cycle shortcuts found")
            return
        }

        guard requestAccessibilityTrustIfNeeded(promptIfNeeded: promptIfNeeded) else {
            stop()
            status = .requiresAccessibility
            Log.inputSource.notice("Accessibility permission is required for OS-style cycle prediction")
            return
        }

        startEventTapIfNeeded()
        status = isStarted ? .active : .disabled
    }

    func refreshAuthorizationStatus(promptIfNeeded: Bool) {
        configure(isEnabled: true, promptIfNeeded: promptIfNeeded)
    }

    func shortcutSummary() -> String {
        configuredShortcuts.map(\.displayLabel).joined(separator: ", ")
    }

    func stop() {
        hideEventTap()
        resetCycleSession()
        isStarted = false
    }

    private func startEventTapIfNeeded() {
        guard !isStarted else {
            return
        }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<InputSourceCyclePredictionMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.handleEvent(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            Log.inputSource.error("Failed to create event tap for input-source cycle prediction")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        runLoopSource = source
        isStarted = true

        Log.inputSource.info("Input-source cycle prediction monitor started")
    }

    func resetCycleSession() {
        activeShortcut = nil
        shadowInputSourceID = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            handleKeyDown(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenableEventTapIfNeeded()
        default:
            break
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = normalizedModifiers(from: event.flags)

        guard let shortcut = shortcuts.first(where: {
            $0.keyCode == keyCode && $0.modifiers == modifiers
        }) else {
            return
        }

        let availableInputSources = inputSourceManager.availableInputSources()
        guard availableInputSources.count > 1 else {
            return
        }

        let baseInputSourceID: String
        if activeShortcut == shortcut, let shadowInputSourceID {
            baseInputSourceID = shadowInputSourceID
        } else {
            baseInputSourceID =
                inputSourceManager.currentInputSource()?.id ??
                availableInputSources.first?.id ??
                ""
        }

        guard
            let currentIndex = availableInputSources.firstIndex(where: { $0.id == baseInputSourceID })
        else {
            return
        }

        let delta = shortcut.direction == .next ? 1 : -1
        let nextIndex = (currentIndex + delta + availableInputSources.count) % availableInputSources.count
        let predictedInputSource = availableInputSources[nextIndex]

        activeShortcut = shortcut
        shadowInputSourceID = predictedInputSource.id

        Log.inputSource.debug(
            "Predicted \(shortcut.direction == .next ? "next" : "previous", privacy: .public) input source as \(predictedInputSource.id, privacy: .public)"
        )

        DispatchQueue.main.async { [weak self] in
            self?.predictionHandler?(predictedInputSource)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        guard let activeShortcut else {
            return
        }

        let currentModifiers = normalizedModifiers(from: event.flags)
        let requiredRawValue = activeShortcut.modifiers.rawValue

        if currentModifiers.rawValue & requiredRawValue != requiredRawValue {
            resetCycleSession()
        }
    }

    private func resolveConfiguredShortcuts() -> [Shortcut] {
        guard
            let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
            let symbolicHotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any]
        else {
            return []
        }

        let definitions: [(id: String, direction: Direction)] = [
            ("60", .previous),
            ("61", .next),
            ("64", .next),
            ("65", .previous)
        ]

        return definitions.compactMap { definition -> Shortcut? in
            guard
                let entry = symbolicHotKeys[definition.id] as? [String: Any],
                let enabled = entry["enabled"] as? NSNumber,
                enabled.boolValue,
                let value = entry["value"] as? [String: Any],
                let parameters = value["parameters"] as? [NSNumber],
                parameters.count >= 3
            else {
                return nil
            }

            let keyCode = parameters[1].int64Value
            let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(parameters[2].uint64Value))
                .intersection(.deviceIndependentFlagsMask)

            guard modifierFlags.contains(.command) || modifierFlags.contains(.control) else {
                return nil
            }

            return Shortcut(
                keyCode: keyCode,
                modifiers: modifierFlags,
                direction: definition.direction
            )
        }
    }

    private func reloadConfiguredShortcuts() {
        shortcuts = resolveConfiguredShortcuts()
        configuredShortcuts = shortcuts.map(makeShortcutDescriptor(from:))
    }

    private func normalizedModifiers(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
            .intersection(.deviceIndependentFlagsMask)
    }

    private func requestAccessibilityTrustIfNeeded(promptIfNeeded: Bool) -> Bool {
        if promptIfNeeded {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        return AXIsProcessTrusted()
    }

    private func reenableEventTapIfNeeded() {
        guard let eventTap else {
            return
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        Log.inputSource.notice("Re-enabled input-source cycle prediction event tap")
    }

    private func hideEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
    }

    private func makeShortcutDescriptor(from shortcut: Shortcut) -> InputSourceCycleShortcutDescriptor {
        let modifierLabels = modifierLabels(for: shortcut.modifiers)
        let keyLabel = keyLabel(for: shortcut.keyCode)
        let title = (modifierLabels + [keyLabel]).joined(separator: "+")
        let directionTitle = shortcut.direction == .next ? "Next Source" : "Previous Source"

        return InputSourceCycleShortcutDescriptor(
            title: title,
            directionTitle: directionTitle
        )
    }

    private func modifierLabels(for modifiers: NSEvent.ModifierFlags) -> [String] {
        var labels: [String] = []

        if modifiers.contains(.command) {
            labels.append("Cmd")
        }
        if modifiers.contains(.control) {
            labels.append("Control")
        }
        if modifiers.contains(.option) {
            labels.append("Option")
        }
        if modifiers.contains(.shift) {
            labels.append("Shift")
        }

        return labels
    }

    private func keyLabel(for keyCode: Int64) -> String {
        switch keyCode {
        case 0: "A"
        case 1: "S"
        case 2: "D"
        case 3: "F"
        case 4: "H"
        case 5: "G"
        case 6: "Z"
        case 7: "X"
        case 8: "C"
        case 9: "V"
        case 11: "B"
        case 12: "Q"
        case 13: "W"
        case 14: "E"
        case 15: "R"
        case 16: "Y"
        case 17: "T"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        case 30: "]"
        case 31: "O"
        case 32: "U"
        case 33: "["
        case 34: "I"
        case 35: "P"
        case 37: "L"
        case 38: "J"
        case 39: "'"
        case 40: "K"
        case 41: ";"
        case 42: "\\"
        case 43: ","
        case 44: "/"
        case 45: "N"
        case 46: "M"
        case 47: "."
        case 49: "Space"
        default:
            "KeyCode \(keyCode)"
        }
    }
}
