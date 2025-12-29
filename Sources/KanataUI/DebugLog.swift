// DebugLog.swift
// Centralized logging using Apple's unified logging system (os.log).
//
// =============================================================================
// APPLE'S UNIFIED LOGGING SYSTEM (os.log)
// =============================================================================
//
// os.log is Apple's recommended logging system for macOS/iOS apps. Benefits:
//
// 1. PERFORMANCE: Log messages are compiled efficiently; disabled log levels
//    have near-zero overhead.
//
// 2. PERSISTENCE: Logs are stored by the system and viewable in Console.app.
//    They persist across app launches and system reboots (for some time).
//
// 3. FILTERING: Console.app can filter by subsystem, category, and log level.
//    Use the subsystem (bundle ID) to see only your app's logs.
//
// 4. PRIVACY: Sensitive data can be marked as private and redacted in logs.
//
// To view logs in Console.app:
// 1. Open Console.app
// 2. Select your Mac in the sidebar
// 3. In the search field, enter: subsystem:com.nikolai.KanataUI
// 4. Enable "Include Info Messages" and "Include Debug Messages" in Action menu
//
// =============================================================================
// LOGGER vs os_log
// =============================================================================
//
// Apple provides two APIs:
// - os_log(): C-style function (older API)
// - Logger: Swift struct (modern API, iOS 14+ / macOS 11+)
//
// Logger is preferred for Swift code because:
// - Type-safe string interpolation
// - Cleaner syntax
// - Better Swift integration
//
// =============================================================================

import Foundation
import os.log  // Apple's unified logging framework

// -----------------------------------------------------------------------------
// @MainActor SINGLETON
// -----------------------------------------------------------------------------
// @MainActor ensures thread-safe access. While Logger itself is thread-safe,
// using @MainActor keeps consistency with how this class is used throughout
// the app (called from @MainActor contexts like KanataManager).
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
    // -------------------------------------------------------------------------
    static let shared = DebugLog()

    // -------------------------------------------------------------------------
    // APPLE'S LOGGER
    // -------------------------------------------------------------------------
    // Logger is Apple's modern logging API.
    //
    // Parameters:
    // - subsystem: Your app's bundle identifier (reverse DNS notation).
    //              Used to filter logs in Console.app.
    // - category: A logical grouping within your app (e.g., "network", "ui").
    //
    // Logs appear in Console.app and can be filtered by subsystem/category.
    // -------------------------------------------------------------------------
    private let logger = Logger(subsystem: "com.nikolai.KanataUI", category: "debug")

    // -------------------------------------------------------------------------
    // BUNDLE IDENTIFIER CONSTANT
    // -------------------------------------------------------------------------
    // The bundle identifier used for logging. Exposed as a static property
    // so it can be referenced when opening Console.app with a filter.
    // -------------------------------------------------------------------------
    static let subsystem = "com.nikolai.KanataUI"

    // -------------------------------------------------------------------------
    // LOG LEVELS
    // -------------------------------------------------------------------------
    // Enum for log severity. Maps to Logger's built-in methods.
    // -------------------------------------------------------------------------
    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    // -------------------------------------------------------------------------
    // PRIVATE INITIALIZER
    // -------------------------------------------------------------------------
    // Making init() private enforces the singleton pattern.
    // -------------------------------------------------------------------------
    private init() {}

    // -------------------------------------------------------------------------
    // log(_:level:) - LOG A MESSAGE
    // -------------------------------------------------------------------------
    // Logs a message at the specified level using Apple's Logger.
    //
    // The default parameter `level: .info` means callers can omit it:
    //   DebugLog.shared.log("message")          // level = .info
    //   DebugLog.shared.log("error", level: .error)
    //
    // LOG LEVEL VISIBILITY:
    // - .error: Always visible in Console.app
    // - .warning: Visible by default
    // - .info: Hidden by default; enable "Include Info Messages" in Console.app
    //
    // Also prints to stdout for immediate visibility during development
    // (when running from Xcode or terminal).
    // -------------------------------------------------------------------------
    func log(_ message: String, level: Level = .info) {
        // Log to Apple's unified logging system
        switch level {
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        }

        // Also print to stdout for development visibility
        // This is helpful when running from Xcode or terminal
        print("[\(level.rawValue)] \(message)")
    }
}
