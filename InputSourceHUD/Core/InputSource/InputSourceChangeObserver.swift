import Carbon
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
