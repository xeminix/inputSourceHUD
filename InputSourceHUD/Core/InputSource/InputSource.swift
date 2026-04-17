import Foundation

struct InputSource: Identifiable, Codable, Hashable {
    let id: String
    let localizedName: String
    let shortLabel: String
}

extension InputSource {
    var hudLanguageName: String {
        switch id {
        case "com.apple.keylayout.ABC":
            "영어"
        case "com.apple.inputmethod.Korean.2SetKorean":
            "한국어"
        default:
            localizedName
        }
    }

    var hudDetailName: String {
        switch id {
        case "com.apple.keylayout.ABC":
            "ABC"
        case "com.apple.inputmethod.Korean.2SetKorean":
            "두벌식"
        default:
            localizedName
        }
    }
}
