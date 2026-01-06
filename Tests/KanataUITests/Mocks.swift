// Mocks.swift
// Mock implementations of protocols for unit testing.
//
// =============================================================================
// MOCK OBJECTS IN TESTING
// =============================================================================
//
// Mock objects are fake implementations of dependencies used during testing.
// They allow us to:
//
// 1. ISOLATE: Test one unit without its real dependencies
// 2. CONTROL: Set up specific scenarios (success, failure, edge cases)
// 3. VERIFY: Check that the right methods were called with the right arguments
// 4. SPEED: Avoid slow operations (network, disk, process spawning)
//
// MOCKS VS STUBS VS FAKES:
// - Stub: Returns canned data, doesn't track calls
// - Mock: Returns canned data AND tracks/verifies calls
// - Fake: A working implementation, but simplified (e.g., in-memory database)
//
// Our "mocks" are technically mocks: they return configurable data AND
// track whether methods were called and with what arguments.
//
// =============================================================================
// @testable import
// =============================================================================
//
// `@testable import KanataUI` is special test-only import that:
// - Imports the module for testing
// - Makes `internal` members accessible (normally only `public` is visible)
//
// This lets tests access types like AppState, KanataManager, etc. without
// making them public. In production, these types are internal to the module.
//
// =============================================================================

import Foundation
@testable import KanataUI

// -----------------------------------------------------------------------------
// MockProcessLauncher - FAKE PROCESS MANAGEMENT
// -----------------------------------------------------------------------------
// This mock replaces RealProcessLauncher for testing. Instead of launching
// actual processes, it:
// - Returns configurable results (success with PID, or throws an error)
// - Records what methods were called and with what arguments
// - Reports configurable process status
//
// DESIGN PATTERN: This uses the "Spy" pattern - it records interactions
// for later verification.
// -----------------------------------------------------------------------------

@MainActor
final class MockProcessLauncher: ProcessLauncher {
    // -------------------------------------------------------------------------
    // CONFIGURABLE BEHAVIOR
    // -------------------------------------------------------------------------
    // These properties control what the mock returns/does. Tests set these
    // before calling methods to simulate different scenarios.
    //
    // Result<Int, Error> is Swift's built-in type for success/failure:
    // - .success(12345) - operation succeeded with value 12345
    // - .failure(someError) - operation failed with error
    // -------------------------------------------------------------------------

    /// What launch() should return. Defaults to success with PID 12345.
    var launchResult: Result<Int, Error> = .success(12345)

    /// Whether isProcessRunning() should return true or false.
    /// Note: After terminate() succeeds, this is reset to true so that
    /// a newly launched process can be considered running.
    var isRunning = true

    /// If true, automatically reset isRunning to true after terminate.
    /// This simulates the scenario where a new process is launched after termination.
    var autoResetIsRunning = true

    // -------------------------------------------------------------------------
    // CALL TRACKING (SPY PATTERN)
    // -------------------------------------------------------------------------
    // These properties record what happened during tests. After calling
    // the code under test, you can verify these values.
    //
    // Example test assertion:
    //   manager.stopKanata()
    //   #expect(mockLauncher.terminateCalled)
    //   #expect(mockLauncher.terminatedPID == 12345)
    // -------------------------------------------------------------------------

    /// Whether terminate() was called
    var terminateCalled = false

    /// The PID passed to terminate()
    var terminatedPID: Int?

    /// The signal passed to terminate()
    var terminatedSignal: Int32?

    /// What terminate() should return. Defaults to true (success).
    /// Set to false to simulate termination failure (e.g., user cancelled
    /// password prompt or permission denied).
    var terminateResult = true

    // -------------------------------------------------------------------------
    // PROTOCOL IMPLEMENTATIONS
    // -------------------------------------------------------------------------

    func launch(command: String) throws -> Int {
        // Use switch to handle the Result type
        switch launchResult {
        case .success(let pid):
            return pid
        case .failure(let error):
            throw error
        }
    }

    /// Mock implementation of terminate() that returns configurable result.
    ///
    /// UPDATED (v1.0.1): Now returns Bool to match updated protocol.
    /// The return value indicates whether termination succeeded:
    /// - true: Process was killed successfully
    /// - false: Termination failed (permission denied, user cancelled, etc.)
    ///
    /// Tests can control this via the `terminateResult` property.
    func terminate(pid: Int, signal: Int32) -> Bool {
        // Record the call for later verification
        terminateCalled = true
        terminatedPID = pid
        terminatedSignal = signal

        // If termination "succeeds" and autoResetIsRunning is false,
        // set isRunning to false to simulate the process stopping.
        // If autoResetIsRunning is true (default), keep isRunning = true
        // so that subsequent process checks (for a new process) succeed.
        if terminateResult && !autoResetIsRunning {
            isRunning = false
        }

        return terminateResult
    }

    func isProcessRunning(pid: Int) -> Bool {
        // Return whatever the test configured
        isRunning
    }
}

// -----------------------------------------------------------------------------
// MockSystemDialogs - FAKE UI DIALOGS
// -----------------------------------------------------------------------------
// This mock replaces RealSystemDialogs for testing. Instead of showing
// actual modal dialogs (which would block tests), it:
// - Records that showFatalAlert was called
// - Returns configurable results for runPrivilegedScript
// - Does NOT terminate the application (unlike the real implementation)
// -----------------------------------------------------------------------------

@MainActor
final class MockSystemDialogs: SystemDialogs {
    // -------------------------------------------------------------------------
    // CALL TRACKING
    // -------------------------------------------------------------------------

    /// Whether showFatalAlert() was called
    var fatalAlertShown = false

    /// Whether showAlert() (non-fatal) was called
    /// ADDED (v1.0.1): Track non-fatal alerts separately from fatal alerts
    var alertShown = false

    /// Whether showConfigErrorAlert() was called
    var configErrorAlertShown = false

    /// The title passed to showFatalAlert(), showAlert(), or showConfigErrorAlert()
    var lastAlertTitle: String?

    /// The message passed to showFatalAlert(), showAlert(), or showConfigErrorAlert()
    var lastAlertMessage: String?

    /// The config path passed to showConfigErrorAlert()
    var lastConfigPath: String?

    // -------------------------------------------------------------------------
    // CONFIGURABLE BEHAVIOR
    // -------------------------------------------------------------------------

    /// What runPrivilegedScript() should return
    var privilegedScriptResult: Result<String, Error> = .success("12345")

    /// What launchPrivilegedProcess() should return (PID or error)
    var launchPrivilegedProcessResult: Result<Int, Error> = .success(12345)

    /// Whether to simulate NSApplication.terminate() - usually false in tests
    var shouldQuitOnFatalAlert = false

    /// What showConfigErrorAlert() should return. Defaults to quit.
    /// Tests can set this to simulate different user choices.
    var configErrorAlertResult: ConfigErrorAction = .quit

    // -------------------------------------------------------------------------
    // PROTOCOL IMPLEMENTATIONS
    // -------------------------------------------------------------------------

    func showFatalAlert(title: String, message: String) {
        // Record the call - tests can verify this was called
        fatalAlertShown = true
        lastAlertTitle = title
        lastAlertMessage = message

        // IMPORTANT: We do NOT call NSApplication.shared.terminate(nil)!
        // The real implementation does, but that would kill our test runner.
        // Tests can check shouldQuitOnFatalAlert if needed.
    }

    /// Mock implementation of showAlert() (non-fatal alerts).
    ///
    /// ADDED (v1.0.1): New method for non-fatal alerts that don't quit the app.
    /// Used when termination fails and we want to inform the user without
    /// exiting (e.g., "Failed to stop kanata - you can try again").
    func showAlert(title: String, message: String) {
        // Record the call - tests can verify this was called
        alertShown = true
        lastAlertTitle = title
        lastAlertMessage = message
        // Note: Unlike showFatalAlert, this doesn't terminate anything
    }

    /// Mock implementation of showConfigErrorAlert().
    ///
    /// Returns the configurable result without showing any UI.
    /// Tests can set configErrorAlertResult to simulate different user choices.
    func showConfigErrorAlert(title: String, message: String, configPath: String) -> ConfigErrorAction {
        configErrorAlertShown = true
        lastAlertTitle = title
        lastAlertMessage = message
        lastConfigPath = configPath
        return configErrorAlertResult
    }

    func runPrivilegedScript(_ script: String) throws -> String {
        switch privilegedScriptResult {
        case .success(let output):
            return output
        case .failure(let error):
            throw error
        }
    }

    /// Mock implementation of launchPrivilegedProcess().
    ///
    /// Returns a configurable PID or throws an error based on launchPrivilegedProcessResult.
    /// Tests can configure this to simulate successful launch or various failure modes.
    func launchPrivilegedProcess(
        executablePath: String,
        arguments: [String],
        logFile: String
    ) throws -> Int {
        switch launchPrivilegedProcessResult {
        case .success(let pid):
            return pid
        case .failure(let error):
            throw error
        }
    }
}

// -----------------------------------------------------------------------------
// MockAppTerminator - FAKE APP TERMINATION
// -----------------------------------------------------------------------------
// This mock replaces RealAppTerminator for testing. Instead of actually
// terminating the test process, it just records that termination was requested.
// -----------------------------------------------------------------------------

@MainActor
final class MockAppTerminator: AppTerminator {
    /// Whether terminate() was called
    var terminateCalled = false

    func terminate() {
        terminateCalled = true
        // Don't actually terminate - that would kill the test runner!
    }
}

// -----------------------------------------------------------------------------
// MockConfigValidator - FAKE CONFIG VALIDATION
// -----------------------------------------------------------------------------
// This mock replaces RealConfigValidator for testing. Instead of running
// the actual `kanata --check` command, it returns configurable results.
//
// This allows tests to:
// - Simulate successful validation
// - Simulate validation failures with specific error messages
// - Test the config error dialog flow
// -----------------------------------------------------------------------------

@MainActor
final class MockConfigValidator: ConfigValidator {
    // -------------------------------------------------------------------------
    // CONFIGURABLE BEHAVIOR
    // -------------------------------------------------------------------------

    /// What validate() should do. Defaults to success (no error).
    /// Set to an error message to simulate validation failure.
    var validationError: String?

    /// Whether validate() was called
    var validateCalled = false

    /// The path passed to validate()
    var lastValidatedPath: String?

    // -------------------------------------------------------------------------
    // PROTOCOL IMPLEMENTATION
    // -------------------------------------------------------------------------

    func validate(configPath: String) throws {
        validateCalled = true
        lastValidatedPath = configPath

        if let error = validationError {
            throw KanataError.configInvalid(error)
        }
        // No error means validation passed
    }
}

// -----------------------------------------------------------------------------
// MockFileManager - FAKE FILE SYSTEM
// -----------------------------------------------------------------------------
// This mock replaces the real FileManager for testing file existence checks.
//
// INHERITANCE VS PROTOCOL:
// Unlike the other mocks, this INHERITS from FileManager (a class) rather
// than implementing a protocol. This is because:
// - FileManager is an Apple class, not a protocol
// - We only need to override fileExists(atPath:)
// - Inheritance lets us override just what we need
//
// ALTERNATIVE: You could create a FileSystemChecking protocol and have
// both FileManager (via extension) and MockFileManager conform to it.
// That's cleaner but requires more setup.
// -----------------------------------------------------------------------------

final class MockFileManager: FileManager {
    /// The set of paths that "exist" in our fake file system.
    /// Tests add paths here to simulate existing files.
    var existingFiles: Set<String> = []

    // `override` is required because we're replacing a superclass method
    override func fileExists(atPath path: String) -> Bool {
        // Check if the path is in our set of "existing" files
        existingFiles.contains(path)
    }
}
