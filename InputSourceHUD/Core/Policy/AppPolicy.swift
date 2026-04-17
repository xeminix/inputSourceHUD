import Foundation

enum AppPolicy: String, Codable, CaseIterable, Identifiable {
    case force
    case useGlobalDefault
    case ignore

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .force:
            "Force Specific Input Source"
        case .useGlobalDefault:
            "Use Global Default"
        case .ignore:
            "Ignore"
        }
    }
}

struct AppRule: Identifiable, Codable, Hashable {
    let bundleId: String
    var displayName: String
    var policy: AppPolicy
    var inputSourceId: String?

    var id: String {
        bundleId
    }
}
