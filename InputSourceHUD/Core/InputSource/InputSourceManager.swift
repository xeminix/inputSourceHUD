import Carbon
import Foundation

@MainActor
final class InputSourceManager {
    private let preferredEnglishInputSourceID = "com.apple.keylayout.ABC"
    private let preferredKoreanInputSourceID = "com.apple.inputmethod.Korean.2SetKorean"
    private let fallbackInputSources: [InputSource] = [
        InputSource(
            id: "com.apple.keylayout.ABC",
            localizedName: "ABC",
            shortLabel: "ABC"
        ),
        InputSource(
            id: "com.apple.inputmethod.Korean.2SetKorean",
            localizedName: "Korean 2-Set",
            shortLabel: "한"
        )
    ]
    let isSimulatedImplementation = false

    func availableInputSources() -> [InputSource] {
        // Keyboard 카테고리만 필터 — PressAndHold, Character Palette(이모지) 등 제외
        let filter = [
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue,
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray
        let inputSources = sources.compactMap { source -> InputSource? in
            let tisSource = source as! TISInputSource
            // Keyboard layout 또는 Keyboard input mode만 허용 (input method / non-keyboard 제외)
            guard let typeID = stringProperty(kTISPropertyInputSourceType, from: tisSource) else {
                return nil
            }
            let isKeyboardLayout = typeID == (kTISTypeKeyboardLayout as String)
            let isKeyboardInputMode = typeID == (kTISTypeKeyboardInputMode as String)
            guard isKeyboardLayout || isKeyboardInputMode else {
                return nil
            }
            return makeInputSource(from: tisSource)
        }
        let selectableInputSources = supportedSelectableInputSources(from: inputSources)

        if selectableInputSources.isEmpty {
            Log.inputSource.error("Falling back to bundled input source list")
            return fallbackInputSources
        }

        return selectableInputSources
    }

    func currentInputSource() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return fallbackInputSources.first
        }

        return makeInputSource(from: source) ?? fallbackInputSources.first
    }

    @discardableResult
    func switchToInputSource(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID: id as CFString] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray

        guard let firstObject = sources.firstObject else {
            Log.inputSource.error("Requested unavailable input source \(id, privacy: .public)")
            return false
        }

        let source = firstObject as! TISInputSource
        let status = TISSelectInputSource(source)

        if status != noErr {
            Log.inputSource.error("TISSelectInputSource failed with status \(status)")
            return false
        }

        Log.inputSource.notice("Switched input source to \(id, privacy: .public)")
        return true
    }

    private func makeInputSource(from source: TISInputSource) -> InputSource? {
        guard
            let id = stringProperty(kTISPropertyInputSourceID, from: source),
            let localizedName = stringProperty(kTISPropertyLocalizedName, from: source)
        else {
            return nil
        }

        return InputSource(
            id: id,
            localizedName: displayName(for: id, localizedName: localizedName),
            shortLabel: shortLabel(for: id, localizedName: localizedName)
        )
    }

    private func supportedSelectableInputSources(from sources: [InputSource]) -> [InputSource] {
        // 시스템에 활성화된 모든 선택 가능 입력기를 노출.
        // ABC / 두벌식을 앞에 두고, 나머지는 localizedName 순 정렬.
        let preferredIDs: [String] = [preferredEnglishInputSourceID, preferredKoreanInputSourceID]
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

        var ordered: [InputSource] = preferredIDs.compactMap { sourcesByID[$0] }
        let preferredIDSet = Set(preferredIDs)
        let remaining = sources
            .filter { !preferredIDSet.contains($0.id) }
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
        ordered.append(contentsOf: remaining)
        return ordered
    }

    private func stringProperty(_ key: CFString, from source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    private func shortLabel(for id: String, localizedName: String) -> String {
        if id == "com.apple.keylayout.ABC" {
            return "ABC"
        }

        let lowercaseID = id.lowercased()
        let lowercaseName = localizedName.lowercased()

        if lowercaseID.contains("korean") || lowercaseName.contains("korean") || localizedName.contains("한국") {
            return "한"
        }

        if lowercaseID.contains("japanese") || lowercaseName.contains("japanese") || localizedName.contains("日本") {
            return "日"
        }

        let compactName = localizedName.replacingOccurrences(of: " ", with: "")
        return String(compactName.prefix(3)).uppercased()
    }

    private func displayName(for id: String, localizedName: String) -> String {
        switch id {
        case preferredEnglishInputSourceID:
            "ABC"
        case preferredKoreanInputSourceID:
            "두벌식"
        default:
            localizedName
        }
    }
}
