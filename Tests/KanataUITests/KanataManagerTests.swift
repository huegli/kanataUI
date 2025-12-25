import Darwin
import Testing
@testable import KanataUI

@Suite("KanataManager Tests")
@MainActor
struct KanataManagerTests {

    @Test("validateEnvironment succeeds when binary and config exist")
    func validateEnvironmentSuccess() throws {
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
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

        #expect(throws: Never.self) {
            try manager.validateEnvironment()
        }
    }

    @Test("validateEnvironment throws when binary missing")
    func validateEnvironmentMissingBinary() throws {
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

        #expect(throws: KanataError.self) {
            try manager.validateEnvironment()
        }
    }

    @Test("validateEnvironment throws when config missing")
    func validateEnvironmentMissingConfig() throws {
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

        #expect(throws: KanataError.self) {
            try manager.validateEnvironment()
        }
    }

    @Test("startKanata shows alert when binary missing")
    func startKanataMissingBinary() {
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

        manager.startKanata()

        #expect(systemDialogs.fatalAlertShown)
        #expect(systemDialogs.lastAlertTitle == "Kanata Binary Not Found")
        #expect(appState.isRunning == false)
    }

    @Test("startKanata shows alert when config missing")
    func startKanataMissingConfig() {
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

        manager.startKanata()

        #expect(systemDialogs.fatalAlertShown)
        #expect(systemDialogs.lastAlertTitle == "Config File Not Found")
        #expect(appState.isRunning == false)
    }

    @Test("startKanata sets running state on success")
    func startKanataSuccess() {
        let appState = AppState()
        let processLauncher = MockProcessLauncher()
        let systemDialogs = MockSystemDialogs()
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

        manager.startKanata()

        #expect(appState.isRunning)
        #expect(appState.kanataPID == 12345)
        #expect(!systemDialogs.fatalAlertShown)
    }

    @Test("stopKanata terminates process and updates state")
    func stopKanata() {
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

        manager.stopKanata()

        #expect(!appState.isRunning)
        #expect(appState.kanataPID == nil)
        #expect(processLauncher.terminateCalled)
        #expect(processLauncher.terminatedPID == 12345)
        #expect(processLauncher.terminatedSignal == SIGTERM)
    }

    @Test("cleanup stops kanata if running")
    func cleanupStopsKanata() {
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

        manager.cleanup()

        #expect(!appState.isRunning)
        #expect(processLauncher.terminateCalled)
    }

    @Test("cleanup does nothing if not running")
    func cleanupNoOp() {
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

        manager.cleanup()

        #expect(!processLauncher.terminateCalled)
    }
}
