import Foundation

enum ProcessLaunchError: Error {
    case launchFailed(String)
    case userCancelled
}

@MainActor
protocol ProcessLauncher {
    func launch(command: String) throws -> Int
    func terminate(pid: Int, signal: Int32)
    func isProcessRunning(pid: Int) -> Bool
}
