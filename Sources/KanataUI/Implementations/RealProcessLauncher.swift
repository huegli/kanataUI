import Foundation

@MainActor
final class RealProcessLauncher: ProcessLauncher {
    func launch(command: String) throws -> Int {
        DebugLog.shared.log("ProcessLauncher.launch: \(command)")

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
            DebugLog.shared.log("ProcessLauncher.launch failed to get PID", level: .error)
            throw ProcessLaunchError.launchFailed("Failed to get PID")
        }

        DebugLog.shared.log("ProcessLauncher.launch returned PID: \(pid)")
        return pid
    }

    func terminate(pid: Int, signal: Int32) {
        DebugLog.shared.log("ProcessLauncher.terminate PID \(pid) with signal \(signal)")

        // First try direct kill (works if we own the process)
        let result = kill(Int32(pid), signal)
        if result == 0 {
            DebugLog.shared.log("kill() succeeded")
            return
        }

        let errnoValue = errno
        DebugLog.shared.log("kill() returned: \(result), errno: \(errnoValue)")

        // If EPERM, the process is running as root - use sudo kill
        if errnoValue == EPERM {
            DebugLog.shared.log("Process is root-owned, using sudo kill")
            do {
                let script = "kill -\(signal) \(pid)"
                let appleScript = "do shell script \"\(script)\" with administrator privileges"

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", appleScript]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                try process.run()
                process.waitUntilExit()

                DebugLog.shared.log("sudo kill completed with status: \(process.terminationStatus)")
            } catch {
                DebugLog.shared.log("sudo kill failed: \(error)", level: .error)
            }
        }
    }

    func isProcessRunning(pid: Int) -> Bool {
        let result = kill(Int32(pid), 0)
        let errnoValue = errno

        // kill(pid, 0) returns:
        //   0: process exists and we can signal it
        //  -1 + EPERM (1): process exists but we can't signal it (running as root)
        //  -1 + ESRCH (3): process does not exist
        let isRunning = (result == 0) || (result == -1 && errnoValue == EPERM)

        if !isRunning {
            DebugLog.shared.log("isProcessRunning(\(pid)): false (kill returned \(result), errno \(errnoValue) ESRCH=no such process)")
        }

        return isRunning
    }
}
