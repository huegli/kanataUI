// KanataManager.swift
// Manages the lifecycle of the kanata background process.
//
// =============================================================================
// SWIFT CONCEPTS DEMONSTRATED
// =============================================================================
//
// 1. ENUMS WITH ASSOCIATED VALUES
//    Swift enums can carry data. KanataError.launchFailed(String) holds an
//    error message. This is more expressive than simple error codes.
//
// 2. SWIFT CONCURRENCY (@MainActor)
//    @MainActor ensures code runs on the main thread. This is critical for:
//    - UI updates (must happen on main thread)
//    - Preventing race conditions with shared state
//
// 3. PROTOCOLS FOR DEPENDENCY INJECTION
//    The class depends on ProcessLauncher and SystemDialogs protocols, not
//    concrete implementations. This allows injecting mock implementations
//    for testing.
//
// 4. ERROR HANDLING (throws, do-catch)
//    Swift uses throwing functions and do-catch blocks instead of exceptions.
//    This makes error handling explicit and checked at compile time.
//
// 5. STATIC PROPERTIES
//    `static` properties belong to the type itself, not instances.
//    They're accessed as KanataManager.kanataBinaryPath.
//
// =============================================================================
// MACOS PROCESS MANAGEMENT PATTERNS
// =============================================================================
//
// - Use SIGTERM (not SIGKILL) for graceful shutdown
// - Monitor child processes to detect crashes
// - Handle privilege escalation (sudo) via osascript
// - Log output for debugging
//
// =============================================================================

import AppKit     // macOS UI framework (includes NSApplication)
import Foundation // Core types (String, Int, Timer, etc.)

// -----------------------------------------------------------------------------
// SWIFT ENUMS - MORE THAN JUST CONSTANTS
// -----------------------------------------------------------------------------
// Unlike enums in many languages, Swift enums are powerful:
// - Can have associated values (data attached to cases)
// - Can have methods and computed properties
// - Can conform to protocols (like Error for throwable enums)
//
// Here, we define custom error types by conforming to the Error protocol.
// This allows us to throw these errors and catch them specifically.
// -----------------------------------------------------------------------------

/// Errors that can occur during kanata process management.
/// Conforming to `Error` allows these to be thrown and caught.
enum KanataError: Error {
    /// The kanata binary was not found at the expected path
    case binaryNotFound

    /// The kanata configuration file was not found
    case configNotFound

    /// Kanata failed to launch. Associated String contains error details.
    /// ASSOCIATED VALUE: The (String) part means this case carries data.
    /// Usage: throw KanataError.launchFailed("Permission denied")
    case launchFailed(String)

    /// The kanata process crashed unexpectedly
    case processCrashed
}

// -----------------------------------------------------------------------------
// @MainActor - SWIFT CONCURRENCY FOR UI SAFETY
// -----------------------------------------------------------------------------
// In macOS/iOS apps, UI updates MUST happen on the main thread. Violating
// this causes crashes or undefined behavior.
//
// @MainActor is a GLOBAL ACTOR that ensures all methods and property accesses
// on this class happen on the main thread. It's enforced at compile time.
//
// Without @MainActor, you'd need manual DispatchQueue.main.async calls
// everywhere, which is error-prone. @MainActor provides compile-time safety.
//
// ACTOR MODEL BASICS:
// Actors are a concurrency primitive that protect their state. Only one
// task can access an actor's mutable state at a time, preventing data races.
// @MainActor is a special actor tied to the main thread.
// -----------------------------------------------------------------------------

@MainActor
final class KanataManager {
    // -------------------------------------------------------------------------
    // STATIC PROPERTIES - TYPE-LEVEL CONSTANTS
    // -------------------------------------------------------------------------
    // `static` means these belong to the KanataManager TYPE, not instances.
    // Access them as: KanataManager.kanataBinaryPath
    //
    // These could also be `static let` for true constants, but `static let`
    // with String literals works the same way.
    //
    // BEST PRACTICE: Use static properties for configuration that doesn't
    // change at runtime. Consider making them configurable via a settings
    // file or user preferences in a more complete application.
    // -------------------------------------------------------------------------
    static let kanataBinaryPath = "/opt/homebrew/bin/kanata"
    static let kanataConfigPath = "/Users/nikolai/dotfiles/kanata.kbd"
    static let logFilePath = "/tmp/kanata-ui.log"

    // -------------------------------------------------------------------------
    // PRIVATE STORED PROPERTIES - DEPENDENCIES
    // -------------------------------------------------------------------------
    // `private` means only this class can access these properties.
    // `let` means they're set once at initialization and never change.
    //
    // These are DEPENDENCIES - objects this class needs to do its work.
    // By accepting them in init(), we enable DEPENDENCY INJECTION.
    // -------------------------------------------------------------------------

    /// Handles launching and terminating processes
    private let processLauncher: ProcessLauncher

    /// Shows alerts and runs privileged scripts
    private let systemDialogs: SystemDialogs

    /// The shared application state (running status, PID)
    private let appState: AppState

    /// File system operations (checking if files exist)
    private let fileManager: FileManager

    /// Timer for monitoring the kanata process
    private var monitorTimer: Timer?

    // -------------------------------------------------------------------------
    // INITIALIZER WITH DEPENDENCY INJECTION
    // -------------------------------------------------------------------------
    // DEPENDENCY INJECTION means passing dependencies in rather than creating
    // them internally. Benefits:
    //
    // 1. TESTABILITY: Tests can inject mock implementations
    // 2. FLEXIBILITY: Easy to swap implementations
    // 3. DECOUPLING: This class doesn't know about concrete implementations
    //
    // The `= .default` provides a default value, making the parameter optional.
    // This is convenient for production use while still allowing test injection.
    // -------------------------------------------------------------------------
    init(
        appState: AppState,
        processLauncher: ProcessLauncher,
        systemDialogs: SystemDialogs,
        fileManager: FileManager = .default  // Default parameter value
    ) {
        self.appState = appState
        self.processLauncher = processLauncher
        self.systemDialogs = systemDialogs
        self.fileManager = fileManager

        DebugLog.shared.log("KanataManager initialized")
        DebugLog.shared.log("Binary path: \(Self.kanataBinaryPath)")
        DebugLog.shared.log("Config path: \(Self.kanataConfigPath)")
    }

    // -------------------------------------------------------------------------
    // THROWING FUNCTIONS
    // -------------------------------------------------------------------------
    // The `throws` keyword means this function can fail and throw an error.
    // Callers must handle this with try/catch.
    //
    // Swift's error handling is:
    // - EXPLICIT: You must mark functions that can throw
    // - CHECKED: Compiler ensures you handle errors
    // - TYPED: You can catch specific error types
    //
    // Unlike exceptions in Java/C#, Swift errors don't unwind the stack
    // automatically - they're more like Result types under the hood.
    // -------------------------------------------------------------------------

    /// Validates that the kanata binary and config file exist.
    /// - Throws: KanataError.binaryNotFound or KanataError.configNotFound
    func validateEnvironment() throws {
        DebugLog.shared.log("Validating environment...")

        // `guard` is Swift's early-exit statement. If the condition is false,
        // the else block MUST exit (return, throw, break, etc.)
        // This keeps the "happy path" un-indented and readable.
        guard fileManager.fileExists(atPath: Self.kanataBinaryPath) else {
            DebugLog.shared.log("Binary not found at \(Self.kanataBinaryPath)", level: .error)
            throw KanataError.binaryNotFound
        }
        DebugLog.shared.log("Binary exists: OK")

        guard fileManager.fileExists(atPath: Self.kanataConfigPath) else {
            DebugLog.shared.log("Config not found at \(Self.kanataConfigPath)", level: .error)
            throw KanataError.configNotFound
        }
        DebugLog.shared.log("Config exists: OK")
    }

    // -------------------------------------------------------------------------
    // startKanata() - MAIN ORCHESTRATION METHOD
    // -------------------------------------------------------------------------
    // This method coordinates the process of starting kanata:
    // 1. Validate environment
    // 2. Build and run the privileged script
    // 3. Parse the returned PID
    // 4. Verify the process started successfully
    // 5. Update state and start monitoring
    //
    // Note this is NOT a throwing function - it handles errors internally
    // by showing alerts to the user.
    // -------------------------------------------------------------------------
    func startKanata() {
        DebugLog.shared.log("=== Starting Kanata ===")

        // ---------------------------------------------------------------------
        // DO-CATCH ERROR HANDLING
        // ---------------------------------------------------------------------
        // `do { try ... } catch { ... }` is Swift's try-catch equivalent.
        // You can catch specific error types for targeted handling.
        // ---------------------------------------------------------------------
        do {
            try validateEnvironment()
        } catch KanataError.binaryNotFound {
            // Catch a specific error type
            systemDialogs.showFatalAlert(
                title: "Kanata Binary Not Found",
                message: "Kanata binary not found at \(Self.kanataBinaryPath)"
            )
            return
        } catch KanataError.configNotFound {
            systemDialogs.showFatalAlert(
                title: "Config File Not Found",
                message: "Config file not found at \(Self.kanataConfigPath)"
            )
            return
        } catch {
            // Catch any other error (the `error` variable is automatically available)
            systemDialogs.showFatalAlert(
                title: "Validation Error",
                message: error.localizedDescription
            )
            return
        }

        // Build the shell script that will run kanata
        // The script:
        // 1. Runs kanata with the config file
        // 2. Redirects stdout/stderr to a log file (> file 2>&1)
        // 3. Runs in background (&)
        // 4. Echoes the PID so we can capture it ($!)
        let script = "\(Self.kanataBinaryPath) --cfg \(Self.kanataConfigPath) > \(Self.logFilePath) 2>&1 & echo $!"

        DebugLog.shared.log("Launch script: \(script)")

        do {
            // Run with admin privileges (will prompt for password)
            let output = try systemDialogs.runPrivilegedScript(script)
            DebugLog.shared.log("Script returned: '\(output)'")

            // Parse the PID from the script output
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.shared.log("Trimmed output: '\(trimmedOutput)'")

            // Int(string) returns Optional<Int> - nil if parsing fails
            guard let pid = Int(trimmedOutput) else {
                DebugLog.shared.log("Failed to parse PID from: '\(trimmedOutput)'", level: .error)
                systemDialogs.showFatalAlert(
                    title: "Launch Failed",
                    message: "Failed to parse process ID from kanata launch.\nOutput was: '\(trimmedOutput)'"
                )
                return
            }

            DebugLog.shared.log("Parsed PID: \(pid)")

            // Verify the process is actually running
            // (it might have exited immediately due to a config error)
            let isRunning = processLauncher.isProcessRunning(pid: pid)
            DebugLog.shared.log("Process \(pid) running check: \(isRunning)")

            if !isRunning {
                // Process exited immediately - read log for error details
                DebugLog.shared.log("Process exited immediately!", level: .error)
                let logContents = readLogFile()
                DebugLog.shared.log("Log file contents:\n\(logContents)", level: .error)

                // .prefix(500) limits the log to first 500 characters
                // to avoid overwhelming the alert dialog
                systemDialogs.showFatalAlert(
                    title: "Kanata Failed to Start",
                    message: "Process exited immediately.\n\nLog output:\n\(logContents.prefix(500))"
                )
                return
            }

            // Success! Update the shared state
            appState.kanataPID = pid
            appState.isRunning = true
            DebugLog.shared.log("Kanata started successfully with PID \(pid)")

            // Start monitoring the process for crashes
            startMonitoring()

        } catch ProcessLaunchError.userCancelled {
            // User clicked Cancel on the password prompt - quit silently
            DebugLog.shared.log("User cancelled sudo prompt")
            NSApplication.shared.terminate(nil)
        } catch {
            // Any other launch error
            DebugLog.shared.log("Launch failed with error: \(error)", level: .error)
            systemDialogs.showFatalAlert(
                title: "Launch Failed",
                message: "Failed to start kanata: \(error.localizedDescription)"
            )
        }
    }

    // -------------------------------------------------------------------------
    // stopKanata() - GRACEFUL SHUTDOWN
    // -------------------------------------------------------------------------
    // Stops the running kanata process by sending SIGTERM (graceful shutdown).
    //
    // UNIX SIGNAL BASICS:
    // - SIGTERM (15): "Please terminate gracefully" - allows cleanup
    // - SIGKILL (9): "Terminate immediately" - cannot be ignored
    //
    // BEST PRACTICE: Always try SIGTERM first. Only use SIGKILL if the
    // process doesn't respond to SIGTERM.
    // -------------------------------------------------------------------------
    func stopKanata() {
        // `guard let` unwraps the optional and exits if nil
        guard let pid = appState.kanataPID else {
            DebugLog.shared.log("stopKanata called but no PID stored")
            return
        }

        DebugLog.shared.log("Stopping Kanata (PID: \(pid))")

        stopMonitoring()
        processLauncher.terminate(pid: pid, signal: SIGTERM)
        appState.kanataPID = nil
        appState.isRunning = false

        DebugLog.shared.log("Kanata stopped")
    }

    /// Called when the app is terminating to ensure cleanup.
    func cleanup() {
        DebugLog.shared.log("Cleanup called, isRunning: \(appState.isRunning)")
        if appState.isRunning {
            stopKanata()
        }
    }

    // -------------------------------------------------------------------------
    // PROCESS MONITORING WITH TIMER
    // -------------------------------------------------------------------------
    // We poll the process status every second to detect if it crashed.
    //
    // ALTERNATIVE APPROACHES:
    // - kqueue/kevent: More efficient but more complex
    // - Process.terminationHandler: Only works for processes we launched
    //   directly (not via osascript)
    //
    // The [weak self] capture prevents a retain cycle - the timer doesn't
    // keep this object alive if it's deallocated.
    // -------------------------------------------------------------------------

    private func startMonitoring() {
        DebugLog.shared.log("Starting process monitoring")

        // Timer.scheduledTimer creates a repeating timer
        // The [weak self] prevents memory leaks (retain cycles)
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Task { @MainActor in ... } ensures we're on the main actor
            // This is needed because the timer callback runs on the main
            // run loop but isn't automatically on the MainActor
            Task { @MainActor in
                self?.checkProcessStatus()
            }
        }
    }

    private func stopMonitoring() {
        DebugLog.shared.log("Stopping process monitoring")
        monitorTimer?.invalidate()  // Stop the timer
        monitorTimer = nil          // Release the reference
    }

    /// Checks if the kanata process is still running; shows alert if crashed.
    private func checkProcessStatus() {
        guard let pid = appState.kanataPID else { return }

        let isRunning = processLauncher.isProcessRunning(pid: pid)

        if !isRunning {
            DebugLog.shared.log("Process \(pid) no longer running - detected crash", level: .error)

            stopMonitoring()
            appState.kanataPID = nil
            appState.isRunning = false

            let logContents = readLogFile()
            DebugLog.shared.log("Log file at crash:\n\(logContents)", level: .error)

            systemDialogs.showFatalAlert(
                title: "Kanata Crashed",
                message: "Kanata process terminated unexpectedly.\n\nLog output:\n\(logContents.prefix(500))"
            )
        }
    }

    // -------------------------------------------------------------------------
    // HELPER METHODS
    // -------------------------------------------------------------------------

    /// Reads the kanata log file for error reporting.
    /// Returns the contents or an error message if reading fails.
    private func readLogFile() -> String {
        do {
            let contents = try String(contentsOfFile: Self.logFilePath, encoding: .utf8)
            return contents.isEmpty ? "(empty log file)" : contents
        } catch {
            return "(could not read log file: \(error.localizedDescription))"
        }
    }
}
