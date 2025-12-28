// DebugLog.swift
// Centralized logging for debugging and error reporting.
//
// =============================================================================
// LOGGING IN MACOS APPLICATIONS
// =============================================================================
//
// macOS provides several logging mechanisms:
//
// 1. print() - Basic console output, good for development
// 2. os.log / Logger - Apple's unified logging system (recommended)
// 3. NSLog - Legacy Objective-C logging
// 4. Custom logging - What we implement here for UI display
//
// This file uses a HYBRID approach:
// - Logger for system-level logging (visible in Console.app)
// - Custom storage for UI display (the Debug Log window)
// - print() for immediate terminal output during development
//
// =============================================================================
// THE SINGLETON PATTERN
// =============================================================================
//
// DebugLog uses the SINGLETON pattern - there's only one instance, accessed
// via `DebugLog.shared`. This is appropriate because:
// - Logging is a global concern
// - We need a single collection of log entries
// - Multiple instances would fragment the logs
//
// CAUTION: Singletons can make testing harder and hide dependencies.
// For most classes, prefer dependency injection. Logging is an exception
// because it's ubiquitous and low-risk.
//
// =============================================================================
// SWIFT NESTED TYPES
// =============================================================================
//
// Swift allows defining types inside other types (nested types). Here,
// `LogEntry` is defined inside `DebugLog`. Benefits:
// - Clear ownership: LogEntry "belongs to" DebugLog
// - Namespace organization: No collision with other "LogEntry" types
// - Access to outer type: Nested types can access private members
//
// =============================================================================

import Foundation
import os.log  // Apple's unified logging framework

// -----------------------------------------------------------------------------
// @MainActor SINGLETON
// -----------------------------------------------------------------------------
// @MainActor ensures thread-safe access to the shared log entries.
// All reads and writes to `entries` happen on the main thread.
// -----------------------------------------------------------------------------

@MainActor
final class DebugLog {
    // -------------------------------------------------------------------------
    // SINGLETON INSTANCE
    // -------------------------------------------------------------------------
    // `static let shared` creates a single, lazily-initialized instance.
    // Swift guarantees thread-safe initialization of static lets.
    //
    // Usage: DebugLog.shared.log("message")
    //
    // The singleton is created on first access and lives for the app's lifetime.
    // -------------------------------------------------------------------------
    static let shared = DebugLog()

    // -------------------------------------------------------------------------
    // APPLE'S LOGGER
    // -------------------------------------------------------------------------
    // Logger is Apple's modern logging API (replaces os_log functions).
    //
    // Parameters:
    // - subsystem: Your app's bundle identifier (reverse DNS notation)
    // - category: A logical grouping within your app
    //
    // Logs appear in Console.app and can be filtered by subsystem/category.
    // They persist across app launches and include system metadata.
    // -------------------------------------------------------------------------
    private let logger = Logger(subsystem: "com.nikolai.KanataUI", category: "debug")

    // -------------------------------------------------------------------------
    // IN-MEMORY LOG STORAGE
    // -------------------------------------------------------------------------
    // `private(set)` means:
    // - External code can READ entries (get)
    // - Only this class can WRITE entries (set)
    //
    // This protects the log from external modification while allowing
    // the UI to display the entries.
    // -------------------------------------------------------------------------
    private(set) var entries: [LogEntry] = []

    // -------------------------------------------------------------------------
    // NESTED TYPES: LogEntry
    // -------------------------------------------------------------------------
    // Struct is the right choice here because:
    // - LogEntry is a simple data container (value type semantics)
    // - Immutable after creation
    // - Copied when stored/passed (no shared references)
    //
    // Identifiable conformance (via `id`) allows use in SwiftUI ForEach.
    // -------------------------------------------------------------------------

    /// A single log entry with timestamp, level, and message.
    struct LogEntry: Identifiable {
        /// Unique identifier for SwiftUI list rendering.
        /// UUID() generates a new unique ID each time.
        let id = UUID()

        /// When the log entry was created
        let timestamp: Date

        /// Severity level (info, warning, error)
        let level: Level

        /// The log message content
        let message: String

        // ---------------------------------------------------------------------
        // NESTED ENUM: Level
        // ---------------------------------------------------------------------
        // Enums inside structs are common for related constants.
        //
        // `String` raw value allows:
        // - Easy conversion to string: level.rawValue → "INFO"
        // - Pattern matching in switch statements
        // ---------------------------------------------------------------------

        /// Log severity levels
        enum Level: String {
            case info = "INFO"
            case warning = "WARN"
            case error = "ERROR"
        }
    }

    // -------------------------------------------------------------------------
    // PRIVATE INITIALIZER
    // -------------------------------------------------------------------------
    // Making init() private enforces the singleton pattern.
    // No one can create another DebugLog instance - they must use .shared.
    // -------------------------------------------------------------------------
    private init() {}

    // -------------------------------------------------------------------------
    // log(_:level:) - ADD A LOG ENTRY
    // -------------------------------------------------------------------------
    // This method:
    // 1. Creates a LogEntry and stores it in our array
    // 2. Sends to Apple's Logger (visible in Console.app)
    // 3. Prints to stdout (visible in Xcode console)
    //
    // The default parameter `level: .info` means callers can omit it:
    //   DebugLog.shared.log("message")          // level = .info
    //   DebugLog.shared.log("error", level: .error)
    // -------------------------------------------------------------------------

    /// Adds a log entry at the specified level.
    ///
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: Severity level (defaults to .info)
    func log(_ message: String, level: LogEntry.Level = .info) {
        // Create and store the entry
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        entries.append(entry)

        // Also log to Apple's unified logging system
        // Each level maps to a Logger method with appropriate priority
        switch level {
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        }

        // Print to stdout for Xcode console visibility
        // This is redundant with Logger but more immediately visible
        print("[\(entry.level.rawValue)] \(message)")
    }

    /// Removes all log entries.
    func clear() {
        entries.removeAll()
    }

    // -------------------------------------------------------------------------
    // COMPUTED PROPERTY: formattedLog
    // -------------------------------------------------------------------------
    // Computed properties look like stored properties but calculate their
    // value each time they're accessed. They're defined with { get { } }
    // or just { } for read-only computed properties.
    //
    // Use computed properties when:
    // - The value can be derived from other data
    // - You want fresh data on each access
    // - Storage would be wasteful or stale
    // -------------------------------------------------------------------------

    /// All log entries formatted as a single string for display/copying.
    var formattedLog: String {
        // Create a date formatter for timestamps
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"  // Hour:Minute:Second.Milliseconds

        // Transform each entry to a formatted string, then join with newlines
        // .map transforms each element; .joined combines into one string
        return entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }
}
