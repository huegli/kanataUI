// RealProcessLauncher.swift
// Production implementation of ProcessLauncher for real process management.
//
// =============================================================================
// PRODUCTION VS TEST IMPLEMENTATIONS
// =============================================================================
//
// This is the "real" implementation of ProcessLauncher, used in production.
// It actually launches processes, sends signals, and checks process status.
//
// The corresponding mock (MockProcessLauncher in Tests/) is used for testing.
// This separation allows us to test business logic without spawning actual
// processes, which would be slow, flaky, and potentially dangerous.
//
// NAMING CONVENTION: "Real" prefix indicates production implementation.
// Some codebases use "Live", "Default", or no prefix (with "Mock" for tests).
//
// =============================================================================
// UNIX PROCESS MANAGEMENT
// =============================================================================
//
// This file uses several Unix system calls and concepts:
//
// - Process: Represents a running program with a unique PID
// - PID: Process IDentifier, an integer assigned by the OS
// - Signals: Inter-process communication mechanism (SIGTERM, SIGKILL, etc.)
// - kill(): System call to send signals (not just for killing!)
// - errno: Global variable set by system calls to indicate errors
//
// =============================================================================

import Foundation

// -----------------------------------------------------------------------------
// PRODUCTION IMPLEMENTATION
// -----------------------------------------------------------------------------

/// Real implementation of ProcessLauncher that manages actual system processes.
///
/// This class uses Foundation's Process class for launching and macOS's kill()
/// system call for termination and status checking.
@MainActor
final class RealProcessLauncher: ProcessLauncher {

    // -------------------------------------------------------------------------
    // launch(command:) - SPAWN A SHELL PROCESS
    // -------------------------------------------------------------------------
    // Uses Foundation's Process class (formerly NSTask) to run shell commands.
    //
    // Process is Apple's high-level wrapper around fork/exec. It provides:
    // - Environment and working directory control
    // - Input/output redirection via Pipe
    // - Synchronous and asynchronous execution
    // -------------------------------------------------------------------------

    func launch(command: String) throws -> Int {
        DebugLog.shared.log("ProcessLauncher.launch: \(command)")

        // Create a new Process instance
        // Process is a class, so this creates a reference type
        let process = Process()

        // Set the executable to /bin/bash
        // URL(fileURLWithPath:) creates a file:// URL from a path string
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        // Pass the command as an argument to bash's -c flag
        // -c means "execute the following string as a command"
        process.arguments = ["-c", command]

        // Set up a Pipe to capture the command's output
        // Pipe creates connected file handles for reading and writing
        let pipe = Pipe()
        process.standardOutput = pipe

        // Discard stderr (send to /dev/null equivalent)
        // FileHandle.nullDevice is the programmatic equivalent of /dev/null
        process.standardError = FileHandle.nullDevice

        // Launch the process
        // This can throw if the executable doesn't exist or can't be run
        try process.run()

        // Wait for the process to complete
        // IMPORTANT: This blocks the current thread!
        // For long-running processes, consider async alternatives
        process.waitUntilExit()

        // Read all data from the pipe
        // readDataToEndOfFile() blocks until EOF (process exit)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        // Parse the output as a PID
        // The command is expected to output just a process ID number
        guard let output = String(data: data, encoding: .utf8),
              let pid = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            DebugLog.shared.log("ProcessLauncher.launch failed to get PID", level: .error)
            throw ProcessLaunchError.launchFailed("Failed to get PID")
        }

        DebugLog.shared.log("ProcessLauncher.launch returned PID: \(pid)")
        return pid
    }

    // -------------------------------------------------------------------------
    // terminate(pid:signal:) - SEND A SIGNAL TO A PROCESS
    // -------------------------------------------------------------------------
    // Uses the Unix kill() system call to send signals to processes.
    //
    // Despite its name, kill() doesn't necessarily kill - it sends any signal.
    // SIGTERM (15) requests graceful termination.
    // SIGKILL (9) forces immediate termination.
    //
    // CHALLENGE: If the target process is running as root (which kanata does),
    // we can't signal it directly - we get EPERM (permission denied).
    // Solution: Use osascript with admin privileges to run kill.
    // -------------------------------------------------------------------------

    func terminate(pid: Int, signal: Int32) {
        DebugLog.shared.log("ProcessLauncher.terminate PID \(pid) with signal \(signal)")

        // First, try to kill the process directly
        // kill() returns 0 on success, -1 on error
        let result = kill(Int32(pid), signal)

        if result == 0 {
            DebugLog.shared.log("kill() succeeded")
            return
        }

        // If kill() failed, check errno to understand why
        // errno is a global variable set by system calls on failure
        // IMPORTANT: Read errno immediately after the failed call!
        let errnoValue = errno
        DebugLog.shared.log("kill() returned: \(result), errno: \(errnoValue)")

        // EPERM (1) means "Operation not permitted"
        // This happens when we try to signal a root-owned process as non-root
        if errnoValue == EPERM {
            DebugLog.shared.log("Process is root-owned, using sudo kill")

            do {
                // Build a kill command
                let script = "kill -\(signal) \(pid)"

                // Wrap it in AppleScript for admin privileges
                // This will prompt the user for their password
                let appleScript = "do shell script \"\(script)\" with administrator privileges"

                // Run osascript to execute the AppleScript
                // /usr/bin/osascript is macOS's AppleScript interpreter
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", appleScript]

                // Discard output - we just care if it succeeds
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

    // -------------------------------------------------------------------------
    // isProcessRunning(pid:) - CHECK IF A PROCESS EXISTS
    // -------------------------------------------------------------------------
    // Uses kill(pid, 0) - a special case that checks process existence
    // without actually sending a signal.
    //
    // Return value interpretation:
    // - 0: Process exists and we can signal it
    // - -1 with EPERM: Process exists but runs as different user (e.g., root)
    // - -1 with ESRCH: Process does not exist (No Such Process)
    //
    // So a process is "running" if kill returns 0 OR returns -1 with EPERM.
    // -------------------------------------------------------------------------

    func isProcessRunning(pid: Int) -> Bool {
        // Send signal 0 (null signal) - just checks if process exists
        let result = kill(Int32(pid), 0)
        let errnoValue = errno

        // Process is running if:
        // - kill succeeded (result == 0), OR
        // - kill failed with EPERM (process exists but is root-owned)
        //
        // EPERM (1) = "Operation not permitted" (process exists, wrong permissions)
        // ESRCH (3) = "No such process" (process doesn't exist)
        let isRunning = (result == 0) || (result == -1 && errnoValue == EPERM)

        if !isRunning {
            DebugLog.shared.log("isProcessRunning(\(pid)): false (kill returned \(result), errno \(errnoValue) ESRCH=no such process)")
        }

        return isRunning
    }
}
