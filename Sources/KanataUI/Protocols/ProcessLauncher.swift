// ProcessLauncher.swift
// Protocol defining process management operations.
//
// =============================================================================
// SWIFT PROTOCOLS - THE FOUNDATION OF ABSTRACTION
// =============================================================================
//
// Protocols in Swift are similar to interfaces in Java/C# or traits in Rust.
// They define a CONTRACT - a set of methods and properties that conforming
// types must implement.
//
// WHY USE PROTOCOLS?
//
// 1. ABSTRACTION: Hide implementation details behind a common interface
// 2. TESTABILITY: Inject mock implementations for unit testing
// 3. FLEXIBILITY: Swap implementations without changing calling code
// 4. DECOUPLING: Code depends on abstractions, not concrete types
//
// This is the "D" in SOLID principles: Dependency Inversion Principle.
// High-level modules should not depend on low-level modules. Both should
// depend on abstractions.
//
// =============================================================================
// PROTOCOL-ORIENTED PROGRAMMING
// =============================================================================
//
// Swift encourages "protocol-oriented programming" - preferring protocols
// and protocol extensions over class inheritance. Benefits:
//
// - Value types (structs) can conform to protocols (no inheritance needed)
// - Multiple protocol conformance (vs single class inheritance)
// - Protocol extensions can provide default implementations
// - Clearer contracts and better composition
//
// =============================================================================

import Foundation

// -----------------------------------------------------------------------------
// ERROR ENUM FOR PROCESS LAUNCH FAILURES
// -----------------------------------------------------------------------------
// Defining specific error types (rather than using generic Error) allows
// callers to catch and handle specific failure cases.
//
// For example, KanataManager catches ProcessLaunchError.userCancelled
// specifically to quit silently (vs showing an error alert).
// -----------------------------------------------------------------------------

/// Errors that can occur when launching or managing processes.
enum ProcessLaunchError: Error {
    /// The process failed to launch. Contains an error message.
    case launchFailed(String)

    /// The user cancelled the operation (e.g., dismissed the password prompt).
    /// This is not really an "error" - it's a user choice - but we use the
    /// error type to propagate this information up the call stack.
    case userCancelled
}

// -----------------------------------------------------------------------------
// @MainActor ON PROTOCOLS
// -----------------------------------------------------------------------------
// Marking a protocol with @MainActor means:
// 1. All conforming types must also be @MainActor
// 2. All methods are assumed to run on the main thread
// 3. Compiler enforces thread safety at compile time
//
// We use @MainActor here because:
// - The callers (KanataManager) are @MainActor
// - Process operations often update UI state
// - It simplifies reasoning about thread safety
// -----------------------------------------------------------------------------

/// Defines operations for launching and managing system processes.
///
/// This protocol abstracts process management, allowing the main application
/// to work with any implementation (real processes for production, mock
/// processes for testing).
///
/// BEST PRACTICE: Keep protocols focused and small. This protocol handles
/// only process lifecycle operations - it doesn't know about kanata, configs,
/// or UI concerns.
@MainActor
protocol ProcessLauncher {
    // -------------------------------------------------------------------------
    // PROTOCOL METHODS
    // -------------------------------------------------------------------------
    // Protocol methods only have DECLARATIONS, not implementations.
    // Conforming types provide the actual implementation.
    //
    // Note: No `func` body - just the signature ending with the return type.
    // -------------------------------------------------------------------------

    /// Launches a shell command and returns the process ID.
    ///
    /// - Parameter command: The shell command to execute
    /// - Returns: The PID of the launched process
    /// - Throws: ProcessLaunchError if launch fails
    ///
    /// SWIFT DOCUMENTATION COMMENTS:
    /// The `///` syntax creates documentation comments that appear in Xcode's
    /// Quick Help and generated documentation. Use them for public APIs.
    func launch(command: String) throws -> Int

    /// Terminates a process by sending a signal.
    ///
    /// - Parameters:
    ///   - pid: The process ID to terminate
    ///   - signal: The signal to send (e.g., SIGTERM for graceful, SIGKILL for force)
    /// - Returns: true if the process was successfully terminated, false otherwise
    ///
    /// IMPORTANT: This method returns a Bool to indicate success or failure.
    /// Callers should check the return value and handle termination failures
    /// appropriately (e.g., show an error to the user or retry with SIGKILL).
    ///
    /// The method may fail if:
    /// - The process requires elevated privileges to terminate (runs as root)
    /// - The user cancels the password prompt for sudo kill
    /// - The process has already exited
    func terminate(pid: Int, signal: Int32) -> Bool

    /// Checks if a process is currently running.
    ///
    /// - Parameter pid: The process ID to check
    /// - Returns: true if the process exists and is running
    ///
    /// This is used to:
    /// - Verify a newly launched process actually started
    /// - Detect if a running process has crashed
    func isProcessRunning(pid: Int) -> Bool
}
