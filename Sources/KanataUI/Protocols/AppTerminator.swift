// AppTerminator.swift
// Protocol for terminating the application.
//
// =============================================================================
// WHY ABSTRACT APP TERMINATION?
// =============================================================================
//
// When testing code that calls NSApplication.shared.terminate(), the test
// process itself gets terminated, causing test failures. By abstracting
// termination behind a protocol, we can:
//
// - Use a real implementation in production that actually quits
// - Use a mock in tests that just records the termination was requested
//
// =============================================================================

import AppKit

// -----------------------------------------------------------------------------
// PROTOCOL DEFINITION
// -----------------------------------------------------------------------------

/// Protocol for terminating the application.
///
/// This abstraction allows unit tests to verify termination is called
/// without actually terminating the test process.
@MainActor
protocol AppTerminator {
    /// Terminates the application.
    func terminate()
}

// -----------------------------------------------------------------------------
// REAL IMPLEMENTATION
// -----------------------------------------------------------------------------

/// Production implementation that actually terminates the app.
@MainActor
final class RealAppTerminator: AppTerminator {
    func terminate() {
        NSApplication.shared.terminate(nil)
    }
}
