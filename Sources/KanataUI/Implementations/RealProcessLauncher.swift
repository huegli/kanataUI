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
    //
    // IMPORTANT: This method returns a Bool indicating success or failure.
    // The caller should check this value and handle failures appropriately
    // (e.g., show an error message or keep the UI in the "running" state).
    //
    // WHY RETURN BOOL INSTEAD OF THROWING?
    // Termination can fail for user-initiated reasons (canceling password prompt)
    // that aren't really "errors" in the traditional sense. Returning Bool lets
    // the caller decide how to handle each case without try-catch boilerplate.
    // -------------------------------------------------------------------------

    func terminate(pid: Int, signal: Int32) -> Bool {
        DebugLog.shared.log("ProcessLauncher.terminate PID \(pid) with signal \(signal)")

        // First, try to kill the process directly
        // kill() returns 0 on success, -1 on error
        let result = kill(Int32(pid), signal)

        if result == 0 {
            DebugLog.shared.log("kill() succeeded")
            // Verify the process actually stopped.
            // Use the same polling strategy as the sudo kill path.
            let delays: [UInt32] = [0, 100_000, 200_000, 500_000, 1_000_000]
            for (index, delay) in delays.enumerated() {
                if delay > 0 {
                    usleep(delay)
                }
                let stillRunning = isProcessRunning(pid: pid)
                DebugLog.shared.log("Process check \(index + 1)/\(delays.count): stillRunning=\(stillRunning)")
                if !stillRunning {
                    DebugLog.shared.log("Process terminated successfully after \(index + 1) check(s)")
                    return true
                }
            }
            DebugLog.shared.log("Warning: Process still running after kill()", level: .warning)
            return false
        }

        // If kill() failed, check errno to understand why
        // errno is a global variable set by system calls on failure
        // IMPORTANT: Read errno immediately after the failed call!
        let errnoValue = errno
        DebugLog.shared.log("kill() returned: \(result), errno: \(errnoValue)")

        // EPERM (1) means "Operation not permitted"
        // This happens when we try to signal a root-owned process as non-root
        if errnoValue == EPERM {
            DebugLog.shared.log("Process is root-owned, trying passwordless sudo kill first")

            // Try passwordless sudo first (if user has configured sudoers for kill)
            if tryPasswordlessSudoKill(pid: pid, signal: signal) {
                return true
            }

            // Fall back to osascript with password prompt
            DebugLog.shared.log("Passwordless sudo failed, falling back to osascript")
            return tryOsascriptKill(pid: pid, signal: signal)
        }

        // For other errors (ESRCH = no such process, etc.), return false
        DebugLog.shared.log("kill() failed with errno \(errnoValue)", level: .error)
        return false
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

    // -------------------------------------------------------------------------
    // PRIVATE HELPER: PASSWORDLESS SUDO PKILL
    // -------------------------------------------------------------------------
    // Attempts to kill kanata using `sudo -n pkill -9 kanata`.
    // The -n flag means non-interactive (no password prompt).
    //
    // Using pkill instead of kill is MORE SECURE because:
    // - The sudoers rule can be specific: /usr/bin/pkill -9 kanata
    // - This only allows killing processes named "kanata", not arbitrary PIDs
    // - Much safer than allowing passwordless /bin/kill
    //
    // Returns true if the process was killed, false if sudo failed or process
    // is still running.
    // -------------------------------------------------------------------------

    private func tryPasswordlessSudoKill(pid: Int, signal: Int32) -> Bool {
        DebugLog.shared.log("Trying passwordless sudo pkill...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // Use pkill with process name - more secure than kill with PID
        // Sudoers rule: username ALL=(ALL) NOPASSWD: /usr/bin/pkill -9 kanata
        process.arguments = ["-n", "/usr/bin/pkill", "-9", "kanata"]

        // Capture output to check for errors
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                DebugLog.shared.log("sudo -n pkill failed: status=\(process.terminationStatus), stderr=\(errorOutput.prefix(200))")
                return false
            }

            DebugLog.shared.log("sudo -n pkill succeeded, verifying process stopped...")

            // Verify the process actually stopped
            return waitForProcessToStop(pid: pid)

        } catch {
            DebugLog.shared.log("sudo -n pkill threw exception: \(error)", level: .error)
            return false
        }
    }

    // -------------------------------------------------------------------------
    // PRIVATE HELPER: OSASCRIPT KILL (WITH PASSWORD PROMPT)
    // -------------------------------------------------------------------------
    // Falls back to using osascript with administrator privileges when
    // passwordless sudo is not configured. This prompts for password.
    // -------------------------------------------------------------------------

    private func tryOsascriptKill(pid: Int, signal: Int32) -> Bool {
        DebugLog.shared.log("Using osascript for privileged kill...")

        do {
            // Build a kill command
            let script = "kill -\(signal) \(pid)"

            // Wrap it in AppleScript for admin privileges
            // This will prompt the user for their password
            let appleScript = "do shell script \"\(script)\" with administrator privileges"

            // Run osascript to execute the AppleScript
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]

            // Capture stderr to detect user cancellation
            let errorPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            // Check for user cancellation (AppleScript error -128)
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                DebugLog.shared.log("osascript kill failed with status: \(process.terminationStatus), stderr: \(errorOutput)", level: .error)

                if errorOutput.contains("-128") {
                    DebugLog.shared.log("User cancelled password prompt for kill")
                }
                return false
            }

            DebugLog.shared.log("osascript kill completed, verifying process stopped...")
            return waitForProcessToStop(pid: pid)

        } catch {
            DebugLog.shared.log("osascript kill threw exception: \(error)", level: .error)
            return false
        }
    }

    // -------------------------------------------------------------------------
    // PRIVATE HELPER: WAIT FOR PROCESS TO STOP
    // -------------------------------------------------------------------------
    // Polls to verify a process has actually terminated after sending a signal.
    // Uses increasing delays to handle both fast exits and slower shutdowns.
    // -------------------------------------------------------------------------

    private func waitForProcessToStop(pid: Int) -> Bool {
        let delays: [UInt32] = [0, 100_000, 200_000, 500_000, 1_000_000]
        for (index, delay) in delays.enumerated() {
            if delay > 0 {
                usleep(delay)
            }
            let stillRunning = isProcessRunning(pid: pid)
            DebugLog.shared.log("Process check \(index + 1)/\(delays.count): stillRunning=\(stillRunning)")
            if !stillRunning {
                DebugLog.shared.log("Process terminated successfully after \(index + 1) check(s)")
                return true
            }
        }

        DebugLog.shared.log("Process still running after all checks", level: .warning)
        return false
    }
}
