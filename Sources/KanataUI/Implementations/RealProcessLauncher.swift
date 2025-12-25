import Foundation

@MainActor
final class RealProcessLauncher: ProcessLauncher {
    func launch(command: String) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8),
              let pid = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProcessLaunchError.launchFailed("Failed to get PID")
        }

        return pid
    }

    func terminate(pid: Int, signal: Int32) {
        kill(Int32(pid), signal)
    }

    func isProcessRunning(pid: Int) -> Bool {
        kill(Int32(pid), 0) == 0
    }
}
