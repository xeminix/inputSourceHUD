import Foundation

struct MenuBarIconRenderer {
    func title(for inputSource: InputSource?) -> String {
        inputSource?.shortLabel ?? "?"
    }
}
