import Foundation
import os.log

@MainActor
final class DebugLog {
    static let shared = DebugLog()

    private let logger = Logger(subsystem: "com.nikolai.KanataUI", category: "debug")
    private(set) var entries: [LogEntry] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        enum Level: String {
            case info = "INFO"
            case warning = "WARN"
            case error = "ERROR"
        }
    }

    private init() {}

    func log(_ message: String, level: LogEntry.Level = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        entries.append(entry)

        switch level {
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        }

        print("[\(entry.level.rawValue)] \(message)")
    }

    func clear() {
        entries.removeAll()
    }

    var formattedLog: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        return entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }
}
