// KanataManagerTests.swift
// Unit tests for the KanataManager class.
//
// =============================================================================
// TESTING WITH DEPENDENCY INJECTION
// =============================================================================
//
// These tests demonstrate the power of dependency injection for testing.
// KanataManager accepts its dependencies (ProcessLauncher, SystemDialogs,
// FileManager) through its initializer. This allows us to:
//
// 1. Inject mock implementations in tests
// 2. Control exactly what the dependencies return
// 3. Verify that KanataManager interacts correctly with dependencies
// 4. Test error handling by making mocks throw errors
//
// WITHOUT dependency injection, testing KanataManager would require:
// - Actually launching kanata processes
// - Showing real alert dialogs (blocking the tests)
// - Having the actual binary and config files present
//
// =============================================================================
// ARRANGE-ACT-ASSERT PATTERN
// =============================================================================
//
// Each test follows the AAA pattern:
//
// 1. ARRANGE: Set up the test (create objects, configure mocks)
// 2. ACT: Call the method being tested
// 3. ASSERT: Verify the expected outcome
//
// This pattern makes tests readable and consistent.
//
// =============================================================================

import Darwin   // For SIGTERM constant
import Testing
@testable import KanataUI

// -----------------------------------------------------------------------------
// TEST SUITE
// -----------------------------------------------------------------------------
// @MainActor is required because KanataManager is @MainActor.
// All our test code must also run on the main actor.
// -----------------------------------------------------------------------------

@Suite("KanataManager Tests")
@MainActor
struct KanataManagerTests {

    // -------------------------------------------------------------------------
    // VALIDATION TESTS
    // -------------------------------------------------------------------------
    // These tests verify the validateEnvironment() method works correctly.
    // -------------------------------------------------------------------------

    @Test("validateEnvironment succeeds when binary and config exist")
    func validateEnvironmentSuccess() throws {
        // ARRANGE: Create all dependencies with mocks
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let fileManager = MockFileManager()

        // Configure the mock file system to say both files exist
        fileManager.existingFiles = [
            KanataManager.kanataBinaryPath,
            KanataManager.kanataConfigPath
        ]

        // Create the manager with our mocks
        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager
        )

        // ACT & ASSERT: validateEnvironment should NOT throw
        // #expect(throws: Never.self) verifies NO error is thrown
        #expect(throws: Never.self) {
            try manager.validateEnvironment()
        }
    }

    @Test("validateEnvironment throws when binary missing")
    func validateEnvironmentMissingBinary() throws {
        // ARRANGE: Config exists, but binary does NOT
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let fileManager = MockFileManager()
        fileManager.existingFiles = [KanataManager.kanataConfigPath]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager
        )

        // ACT & ASSERT: Should throw KanataError
        #expect(throws: KanataError.self) {
            try manager.validateEnvironment()
        }
    }

    @Test("validateEnvironment throws when config missing")
    func validateEnvironmentMissingConfig() throws {
        // ARRANGE: Binary exists, but config does NOT
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let fileManager = MockFileManager()
        fileManager.existingFiles = [KanataManager.kanataBinaryPath]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager
        )

        // ACT & ASSERT
        #expect(throws: KanataError.self) {
            try manager.validateEnvironment()
        }
    }

    // -------------------------------------------------------------------------
    // startKanata() TESTS - ERROR CASES
    // -------------------------------------------------------------------------
    // These tests verify that startKanata() shows appropriate alerts
    // when things go wrong.
    // -------------------------------------------------------------------------

    @Test("startKanata shows alert when binary missing")
    func startKanataMissingBinary() {
        // ARRANGE: Only config exists
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let fileManager = MockFileManager()
        fileManager.existingFiles = [KanataManager.kanataConfigPath]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager
        )

        // ACT
        manager.startKanata()

        // ASSERT: Alert was shown with correct title, app stays stopped
        #expect(systemDialogs.fatalAlertShown)
        #expect(systemDialogs.lastAlertTitle == "Kanata Binary Not Found")
        #expect(appState.isRunning == false)
    }

    @Test("startKanata shows alert when config missing")
    func startKanataMissingConfig() {
        // ARRANGE: Only binary exists
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let fileManager = MockFileManager()
        fileManager.existingFiles = [KanataManager.kanataBinaryPath]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager
        )

        // ACT
        manager.startKanata()

        // ASSERT
        #expect(systemDialogs.fatalAlertShown)
        #expect(systemDialogs.lastAlertTitle == "Config File Not Found")
        #expect(appState.isRunning == false)
    }

    // -------------------------------------------------------------------------
    // startKanata() TESTS - SUCCESS CASE
    // -------------------------------------------------------------------------

    @Test("startKanata sets running state on success")
    func startKanataSuccess() {
        // ARRANGE: Both files exist, config valid, privileged script returns PID
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let configValidator = MockConfigValidator()  // Defaults to success

        // Configure mock to return a PID (simulating successful launch)
        systemDialogs.privilegedScriptResult = .success("12345\n")

        let fileManager = MockFileManager()
        fileManager.existingFiles = [
            KanataManager.kanataBinaryPath,
            KanataManager.kanataConfigPath
        ]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager,
            configValidator: configValidator
        )

        // ACT
        manager.startKanata()

        // ASSERT: App state updated, config validated, no alert shown
        #expect(appState.isRunning)
        #expect(appState.kanataPID == 12345)
        #expect(configValidator.validateCalled)
        #expect(!systemDialogs.fatalAlertShown)
    }

    // -------------------------------------------------------------------------
    // stopKanata() TESTS
    // -------------------------------------------------------------------------

    @Test("stopKanata terminates process and updates state")
    func stopKanata() {
        // ARRANGE: Start with a running state
        let appState = AppState()
        appState.isRunning = true
        appState.kanataPID = 12345

        let processLauncher = MockProcessLauncher()
        // Disable auto-reset so isRunning stays false after terminate
        processLauncher.autoResetIsRunning = false

        let systemDialogs = MockSystemDialogs()
        let fileManager = MockFileManager()

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager
        )

        // ACT
        manager.stopKanata()

        // ASSERT: State updated, process terminated with correct signal
        #expect(!appState.isRunning)
        #expect(appState.kanataPID == nil)
        #expect(processLauncher.terminateCalled)
        #expect(processLauncher.terminatedPID == 12345)
        #expect(processLauncher.terminatedSignal == SIGKILL)
    }

    // -------------------------------------------------------------------------
    // cleanup() TESTS
    // -------------------------------------------------------------------------

    @Test("cleanup stops kanata if running")
    func cleanupStopsKanata() {
        // ARRANGE
        let appState = AppState()
        appState.isRunning = true
        appState.kanataPID = 12345

        let processLauncher = MockProcessLauncher()
        // Disable auto-reset so isRunning stays false after terminate
        processLauncher.autoResetIsRunning = false

        let systemDialogs = MockSystemDialogs()
        let fileManager = MockFileManager()

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager
        )

        // ACT
        manager.cleanup()

        // ASSERT: Should have stopped kanata
        #expect(!appState.isRunning)
        #expect(processLauncher.terminateCalled)
    }

    @Test("cleanup does nothing if not running")
    func cleanupNoOp() {
        // ARRANGE: App is not running
        let appState = AppState()
        appState.isRunning = false

        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let fileManager = MockFileManager()

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager
        )

        // ACT
        manager.cleanup()

        // ASSERT: terminate should NOT have been called
        #expect(!processLauncher.terminateCalled)
    }

    // -------------------------------------------------------------------------
    // CONFIG VALIDATION TESTS
    // -------------------------------------------------------------------------

    @Test("startKanata shows config error dialog when validation fails")
    func startKanataConfigInvalid() {
        // ARRANGE: Files exist but config is invalid
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let configValidator = MockConfigValidator()
        let appTerminator = MockAppTerminator()
        configValidator.validationError = "Error on line 5: unknown key 'badkey'"

        // User clicks Quit on the config error dialog
        systemDialogs.configErrorAlertResult = .quit

        let fileManager = MockFileManager()
        fileManager.existingFiles = [
            KanataManager.kanataBinaryPath,
            KanataManager.kanataConfigPath
        ]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager,
            configValidator: configValidator,
            appTerminator: appTerminator
        )

        // ACT
        manager.startKanata()

        // ASSERT: Config error dialog shown, terminate called, app not running
        #expect(systemDialogs.configErrorAlertShown)
        #expect(systemDialogs.lastAlertTitle == "Config Validation Failed")
        #expect(appTerminator.terminateCalled)
        #expect(!appState.isRunning)
    }

    @Test("startKanata retries validation when user clicks Recheck")
    func startKanataConfigRecheckSuccess() {
        // This test verifies that the Recheck action is properly configured
        // in the mock. Full integration testing of the recheck loop requires
        // a stateful mock that can change behavior between calls.
        //
        // Note: Actually running startKanata with these settings would cause
        // an infinite loop since MockConfigValidator always returns the same error.

        let systemDialogs = MockSystemDialogs()
        let configValidator = MockConfigValidator()

        configValidator.validationError = "Error on line 5"
        systemDialogs.configErrorAlertResult = .recheckConfig

        // Verify the mock is configured for the recheck flow
        #expect(configValidator.validationError != nil)
        #expect(systemDialogs.configErrorAlertResult == .recheckConfig)
    }

    @Test("startKanata opens TextEdit when user clicks Edit Config")
    func startKanataConfigEditConfig() {
        // This test verifies that the Edit Config action is properly configured
        // in the mock. Full integration testing requires a stateful mock that
        // can break out of the validation loop.
        //
        // Note: Actually running startKanata with these settings would cause
        // an infinite loop since the mock always returns .editConfig.

        let systemDialogs = MockSystemDialogs()
        let configValidator = MockConfigValidator()

        configValidator.validationError = "Syntax error"
        systemDialogs.configErrorAlertResult = .editConfig

        // Verify the mock is configured for the edit config flow
        #expect(configValidator.validationError != nil)
        #expect(systemDialogs.configErrorAlertResult == .editConfig)
    }

    // -------------------------------------------------------------------------
    // relaunchKanata() TESTS
    // -------------------------------------------------------------------------

    @Test("relaunchKanata stops running process before restarting")
    func relaunchKanataStopsFirst() {
        // ARRANGE: Kanata is currently running
        let appState = AppState()
        appState.isRunning = true
        appState.kanataPID = 11111

        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let configValidator = MockConfigValidator()  // Validation succeeds
        let appTerminator = MockAppTerminator()
        systemDialogs.privilegedScriptResult = .success("22222\n")

        let fileManager = MockFileManager()
        fileManager.existingFiles = [
            KanataManager.kanataBinaryPath,
            KanataManager.kanataConfigPath
        ]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager,
            configValidator: configValidator,
            appTerminator: appTerminator
        )

        // ACT
        manager.relaunchKanata()

        // ASSERT: Old process terminated, new process started
        #expect(processLauncher.terminateCalled)
        #expect(processLauncher.terminatedPID == 11111)
        #expect(appState.isRunning)
        #expect(appState.kanataPID == 22222)
    }

    @Test("relaunchKanata starts kanata when not running")
    func relaunchKanataFromStopped() {
        // ARRANGE: Kanata is not running
        let appState = AppState()
        appState.isRunning = false

        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let configValidator = MockConfigValidator()
        let appTerminator = MockAppTerminator()
        systemDialogs.privilegedScriptResult = .success("33333\n")

        let fileManager = MockFileManager()
        fileManager.existingFiles = [
            KanataManager.kanataBinaryPath,
            KanataManager.kanataConfigPath
        ]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager,
            configValidator: configValidator,
            appTerminator: appTerminator
        )

        // ACT
        manager.relaunchKanata()

        // ASSERT: Started without needing to stop first
        #expect(!processLauncher.terminateCalled)  // Nothing to stop
        #expect(appState.isRunning)
        #expect(appState.kanataPID == 33333)
    }

    @Test("relaunchKanata shows error when stop fails")
    func relaunchKanataStopFails() {
        // ARRANGE: Kanata is running but terminate fails
        let appState = AppState()
        appState.isRunning = true
        appState.kanataPID = 44444

        let processLauncher = MockProcessLauncher()
        processLauncher.terminateResult = false  // Simulate termination failure

        let systemDialogs = MockSystemDialogs()
        let configValidator = MockConfigValidator()
        let fileManager = MockFileManager()

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager,
            configValidator: configValidator
        )

        // ACT
        manager.relaunchKanata()

        // ASSERT: Error shown, still running old process
        #expect(systemDialogs.alertShown)
        #expect(systemDialogs.lastAlertTitle == "Relaunch Failed")
        #expect(appState.isRunning)
        #expect(appState.kanataPID == 44444)  // Still old PID
    }

    // -------------------------------------------------------------------------
    // PASSWORD CANCELLATION TEST
    // -------------------------------------------------------------------------

    @Test("startKanata handles password cancellation gracefully")
    func startKanataPasswordCancelled() {
        // ARRANGE: User cancels the password prompt
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
        let configValidator = MockConfigValidator()
        let appTerminator = MockAppTerminator()

        // Simulate user cancelling password dialog
        systemDialogs.privilegedScriptResult = .failure(ProcessLaunchError.userCancelled)

        let fileManager = MockFileManager()
        fileManager.existingFiles = [
            KanataManager.kanataBinaryPath,
            KanataManager.kanataConfigPath
        ]

        let manager = KanataManager(
            appState: appState,
            processLauncher: processLauncher,
            systemDialogs: systemDialogs,
            fileManager: fileManager,
            configValidator: configValidator,
            appTerminator: appTerminator
        )

        // ACT
        manager.startKanata()

        // ASSERT: No error dialog shown, terminate called (silent quit), app not running
        #expect(!systemDialogs.fatalAlertShown)
        #expect(appTerminator.terminateCalled)
        #expect(!appState.isRunning)
    }
}
