import Foundation

// Stand-in for os.Logger so the app's service code compiles on Linux.
enum LogPrivacy { case auto, `public`, `private` }

struct LogMessage: ExpressibleByStringInterpolation {
    var text: String
    init(stringLiteral value: String) { text = value }
    init(stringInterpolation: Interpolation) { text = stringInterpolation.text }

    struct Interpolation: StringInterpolationProtocol {
        var text = ""
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { text += literal }
        mutating func appendInterpolation<T>(_ value: T, privacy: LogPrivacy = .auto) { text += "\(value)" }
    }
}

struct Logger {
    let category: String
    static let app = Logger(category: "app")
    static let diary = Logger(category: "diary")
    static let photos = Logger(category: "photos")
    static let push = Logger(category: "push")
    func info(_ message: LogMessage) { print("    [\(category)] \(message.text)") }
    func debug(_ message: LogMessage) { print("    [\(category)] \(message.text)") }
    func error(_ message: LogMessage) { print("    [\(category)] ERROR \(message.text)") }
}
