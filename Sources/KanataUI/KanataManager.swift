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

    /// The kanata configuration file failed validation.
    /// ASSOCIATED VALUE: Contains the error output from `kanata --check`.
    /// Usage: throw KanataError.configInvalid("Error on line 5: unknown key")
    case configInvalid(String)

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
    // validateConfig() - VALIDATE KANATA CONFIGURATION FILE
    // -------------------------------------------------------------------------
    // Runs `kanata --check --cfg <config>` to validate the configuration file
    // before attempting to launch kanata.
    //
    // WHY VALIDATE BEFORE LAUNCHING?
    // - Kanata requires sudo to run (for keyboard access)
    // - If the config is invalid, kanata will fail immediately after prompting
    //   for the password, which is a poor user experience
    // - By validating first (without sudo), we can catch config errors before
    //   the user enters their password
    //
    // The --check flag tells kanata to parse and validate the config without
    // actually starting the keyboard remapping daemon.
    // -------------------------------------------------------------------------

    /// Validates the kanata configuration file using `kanata --check`.
    /// - Throws: KanataError.configInvalid if validation fails
    func validateConfig() throws {
        DebugLog.shared.log("Validating config file...")

        // Build the validation command
        // --check: Validate config without starting kanata
        // --cfg: Path to the configuration file
        let command = "\(Self.kanataBinaryPath) --check --cfg \(Self.kanataConfigPath)"
        DebugLog.shared.log("Validation command: \(command)")

        // Create a Process to run the validation
        // Unlike launching kanata itself, validation doesn't need sudo
        // because it doesn't access the keyboard hardware
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        // Capture both stdout and stderr
        // kanata outputs validation errors to stderr
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            // Read output for logging
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outputData, encoding: .utf8) ?? ""
            let stderr = String(data: errorData, encoding: .utf8) ?? ""

            // terminationStatus 0 means success
            if process.terminationStatus == 0 {
                DebugLog.shared.log("Config validation: OK")
                return
            }

            // Validation failed - combine output for error message
            let errorOutput = stderr.isEmpty ? stdout : stderr
            DebugLog.shared.log("Config validation failed:\n\(errorOutput)", level: .error)
            throw KanataError.configInvalid(errorOutput)
        } catch let error as KanataError {
            // Re-throw KanataError (our own error from above)
            throw error
        } catch {
            // Other errors (e.g., process launch failure)
            DebugLog.shared.log("Config validation process error: \(error)", level: .error)
            throw KanataError.configInvalid("Failed to run validation: \(error.localizedDescription)")
        }
    }

    // -------------------------------------------------------------------------
    // startKanata() - MAIN ORCHESTRATION METHOD
    // -------------------------------------------------------------------------
    // This method coordinates the process of starting kanata:
    // 1. Validate environment (binary and config file exist)
    // 2. Validate config file syntax using `kanata --check`
    // 3. Build and run the privileged script
    // 4. Parse the returned PID
    // 5. Verify the process started successfully
    // 6. Update state and start monitoring
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

        // ---------------------------------------------------------------------
        // CONFIG VALIDATION WITH USER OPTIONS
        // ---------------------------------------------------------------------
        // Validate the config file BEFORE prompting for the password.
        // This provides a better user experience - if the config has errors,
        // we catch them before the user enters their password.
        //
        // If validation fails, the user gets three options:
        // - Quit: Exit the application
        // - Edit Config: Open the config in TextEdit, then show dialog again
        // - Recheck: Re-run validation (useful after editing externally)
        //
        // This loop continues until validation passes or the user quits.
        // ---------------------------------------------------------------------
        var validationPassed = false
        while !validationPassed {
            do {
                try validateConfig()
                validationPassed = true
            } catch KanataError.configInvalid(let errorOutput) {
                // Show the validation error with options
                // Limit to first 500 characters to avoid overwhelming the alert
                let action = systemDialogs.showConfigErrorAlert(
                    title: "Config Validation Failed",
                    message: "The kanata configuration file has errors:\n\n\(String(errorOutput.prefix(500)))",
                    configPath: Self.kanataConfigPath
                )

                switch action {
                case .quit:
                    // User chose to quit - terminate the application
                    NSApplication.shared.terminate(nil)
                    return
                case .editConfig:
                    // User chose to edit - TextEdit was opened by the dialog
                    // Continue the loop to show the dialog again
                    DebugLog.shared.log("Config opened in TextEdit, waiting for recheck...")
                    continue
                case .recheckConfig:
                    // User chose to recheck - continue the loop
                    DebugLog.shared.log("Rechecking config...")
                    continue
                }
            } catch {
                // Unexpected error during validation - show fatal alert
                systemDialogs.showFatalAlert(
                    title: "Config Validation Error",
                    message: error.localizedDescription
                )
                return
            }
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
    // stopKanata() - FORCEFUL PROCESS TERMINATION
    // -------------------------------------------------------------------------
    // Stops the running kanata process by sending SIGKILL (forceful shutdown).
    //
    // UNIX SIGNAL BASICS:
    // - SIGTERM (15): "Please terminate gracefully" - allows cleanup, CAN BE IGNORED
    // - SIGKILL (9): "Terminate immediately" - CANNOT be caught or ignored
    //
    // WHY SIGKILL INSTEAD OF SIGTERM?
    // Kanata runs as a keyboard remapper with low-level system access. Testing
    // showed that SIGTERM was being ignored or taking too long to process.
    // Since kanata doesn't need to perform cleanup (it's stateless - keyboard
    // mappings are restored by the OS when the process exits), SIGKILL is safe
    // and provides reliable, immediate termination.
    //
    // IMPORTANT: This method checks if termination actually succeeded.
    // If the user cancels the password prompt or termination fails for any
    // reason, the UI state remains unchanged (still shows "Running").
    // This prevents the UI from showing "Stopped" when kanata is still running.
    // -------------------------------------------------------------------------
    func stopKanata() {
        // `guard let` unwraps the optional and exits if nil
        guard let pid = appState.kanataPID else {
            DebugLog.shared.log("stopKanata called but no PID stored")
            return
        }

        DebugLog.shared.log("Stopping Kanata (PID: \(pid))")

        // Stop monitoring BEFORE attempting termination to prevent
        // the monitor from detecting the process exit as a "crash"
        stopMonitoring()

        // Attempt to terminate the process using SIGKILL for reliable termination
        // terminate() returns true only if the process was successfully killed
        let success = processLauncher.terminate(pid: pid, signal: SIGKILL)

        if success {
            // Process was successfully terminated - update state
            appState.kanataPID = nil
            appState.isRunning = false
            DebugLog.shared.log("Kanata stopped successfully")
        } else {
            // Termination failed (user cancelled password prompt or other error)
            // Keep the state as "running" since the process is still alive
            DebugLog.shared.log("Failed to stop Kanata - process still running", level: .error)

            // Restart monitoring since the process is still running
            startMonitoring()

            // Show error to user (non-fatal since app doesn't need to quit)
            systemDialogs.showAlert(
                title: "Failed to Stop Kanata",
                message: "Could not terminate the kanata process (PID \(pid)).\n\nThe process may require administrator privileges to stop. You can try again or manually run:\nsudo kill \(pid)"
            )
        }
    }

    // -------------------------------------------------------------------------
    // cleanup() - APP TERMINATION CLEANUP
    // -------------------------------------------------------------------------
    // Called when the app is terminating to ensure the kanata process is stopped.
    //
    // IMPORTANT: This method runs synchronously during app termination.
    // It MUST complete before the app exits, otherwise the kanata process
    // will be orphaned and continue running in the background.
    //
    // Unlike stopKanata(), this method does NOT show error dialogs because:
    // 1. The app is already quitting - dialogs would just delay exit
    // 2. If cleanup fails, the user can manually kill the process
    // -------------------------------------------------------------------------
    func cleanup() {
        DebugLog.shared.log("Cleanup called, isRunning: \(appState.isRunning)")
        if appState.isRunning {
            guard let pid = appState.kanataPID else {
                DebugLog.shared.log("Cleanup: No PID stored")
                return
            }

            DebugLog.shared.log("Cleanup: Stopping kanata (PID: \(pid))")
            stopMonitoring()

            // Attempt termination using SIGKILL - don't show UI alerts during cleanup
            // SIGKILL ensures immediate termination during app quit
            let success = processLauncher.terminate(pid: pid, signal: SIGKILL)

            if success {
                appState.kanataPID = nil
                appState.isRunning = false
                DebugLog.shared.log("Cleanup: Kanata terminated successfully")
            } else {
                // Log the failure but don't show UI - app is exiting anyway
                DebugLog.shared.log("Cleanup: Failed to terminate kanata (PID \(pid)). Process may still be running.", level: .error)
            }
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
