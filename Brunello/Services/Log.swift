import OSLog

/// One logger per area, visible in Xcode's console and the Console app.
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Brunello"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let diary = Logger(subsystem: subsystem, category: "diary")
    static let photos = Logger(subsystem: subsystem, category: "photos")
    static let push = Logger(subsystem: subsystem, category: "push")
}
