import Foundation
@testable import KanataUI

@MainActor
final class MockProcessLauncher: ProcessLauncher {
    var launchResult: Result<Int, Error> = .success(12345)
    var terminateCalled = false
    var terminatedPID: Int?
    var terminatedSignal: Int32?
    var isRunning = true

    func launch(command: String) throws -> Int {
        switch launchResult {
        case .success(let pid):
            return pid
        case .failure(let error):
            throw error
        }
    }

    func terminate(pid: Int, signal: Int32) {
        terminateCalled = true
        terminatedPID = pid
        terminatedSignal = signal
    }

    func isProcessRunning(pid: Int) -> Bool {
        isRunning
    }
}

@MainActor
final class MockSystemDialogs: SystemDialogs {
    var fatalAlertShown = false
    var lastAlertTitle: String?
    var lastAlertMessage: String?
    var privilegedScriptResult: Result<String, Error> = .success("12345")
    var shouldQuitOnFatalAlert = false

    func showFatalAlert(title: String, message: String) {
        fatalAlertShown = true
        lastAlertTitle = title
        lastAlertMessage = message
    }

    func runPrivilegedScript(_ script: String) throws -> String {
        switch privilegedScriptResult {
        case .success(let output):
            return output
        case .failure(let error):
            throw error
        }
    }
}

final class MockFileManager: FileManager {
    var existingFiles: Set<String> = []

    override func fileExists(atPath path: String) -> Bool {
        existingFiles.contains(path)
    }
}
