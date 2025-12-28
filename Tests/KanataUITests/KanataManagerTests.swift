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
        // ARRANGE: Both files exist, privileged script returns PID
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()

        // Configure mock to return a PID (simulating successful launch)
        // Note: The PID comes from runPrivilegedScript, not processLauncher
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
            fileManager: fileManager
        )

        // ACT
        manager.startKanata()

        // ASSERT: App state updated, no alert shown
        #expect(appState.isRunning)
        #expect(appState.kanataPID == 12345)
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
        #expect(processLauncher.terminatedSignal == SIGTERM)
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
}
