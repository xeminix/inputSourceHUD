import OSLog

enum Log {
    private static let subsystem = "com.codequa.inputSourceHUD"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let inputSource = Logger(subsystem: subsystem, category: "inputSource")
    static let hud = Logger(subsystem: subsystem, category: "hud")
    static let storage = Logger(subsystem: subsystem, category: "storage")
}
