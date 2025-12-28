// SystemDialogs.swift
// Protocol defining system dialog and privileged script operations.
//
// =============================================================================
// WHY ABSTRACT SYSTEM DIALOGS?
// =============================================================================
//
// System dialogs (alerts, password prompts) are inherently difficult to test:
// - They require user interaction
// - They block the main thread waiting for user input
// - They're tightly coupled to the macOS windowing system
//
// By abstracting these behind a protocol, we can:
// - Inject a mock that records calls without showing UI
// - Test that the right dialogs are shown in the right situations
// - Avoid modal dialogs blocking our test suite
//
// This is a classic example of the ADAPTER PATTERN - wrapping system
// functionality behind a testable interface.
//
// =============================================================================
// SEPARATION OF CONCERNS
// =============================================================================
//
// Notice this protocol handles TWO related but distinct concerns:
// 1. Showing UI alerts (showFatalAlert)
// 2. Running privileged scripts (runPrivilegedScript)
//
// These are grouped because in macOS, running a privileged script inherently
// involves a system dialog (the password prompt). They're both "things that
// require user interaction and are hard to test."
//
// In a larger app, you might split these into separate protocols.
//
// =============================================================================

import Foundation

// -----------------------------------------------------------------------------
// PROTOCOL DEFINITION
// -----------------------------------------------------------------------------

/// Defines operations for system dialogs and privileged operations.
///
/// This protocol abstracts:
/// - macOS alert dialogs (NSAlert)
/// - Privileged script execution with admin password prompts
///
/// Having this as a protocol allows unit tests to verify that the right
/// dialogs are shown without actually displaying UI.
@MainActor
protocol SystemDialogs {
    // -------------------------------------------------------------------------
    // showFatalAlert - DISPLAY A CRITICAL ERROR
    // -------------------------------------------------------------------------
    // "Fatal" here means the application cannot continue after this error.
    // The implementation (RealSystemDialogs) terminates the app after showing
    // the alert.
    //
    // Design decision: This method doesn't return anything because the app
    // will terminate. The mock implementation just records the call.
    // -------------------------------------------------------------------------

    /// Shows a critical error alert and terminates the application.
    ///
    /// - Parameters:
    ///   - title: The alert's title (e.g., "Kanata Binary Not Found")
    ///   - message: Detailed error message explaining what went wrong
    ///
    /// This is called when the application encounters an unrecoverable error:
    /// - Missing binary or config file
    /// - Process launch failure
    /// - Unexpected process crash
    ///
    /// BEST PRACTICE: Provide clear, actionable error messages. Tell users:
    /// 1. What went wrong
    /// 2. Why it matters
    /// 3. How to fix it (if possible)
    func showFatalAlert(title: String, message: String)

    // -------------------------------------------------------------------------
    // showAlert - DISPLAY A NON-FATAL WARNING OR ERROR
    // -------------------------------------------------------------------------
    // Unlike showFatalAlert, this does NOT terminate the application.
    // Use this for recoverable errors where the user can take action and
    // continue using the app (e.g., failed to stop a process but can retry).
    //
    // WHEN TO USE EACH:
    // - showFatalAlert: App cannot continue (missing files, launch failures)
    // - showAlert: User should be informed but app continues (stop failed)
    // -------------------------------------------------------------------------

    /// Shows an informational or warning alert without terminating the app.
    ///
    /// - Parameters:
    ///   - title: The alert's title
    ///   - message: Detailed message explaining the situation
    ///
    /// Unlike showFatalAlert, this method returns after the user dismisses
    /// the alert, allowing the application to continue running.
    func showAlert(title: String, message: String)

    // -------------------------------------------------------------------------
    // runPrivilegedScript - EXECUTE WITH ADMIN RIGHTS
    // -------------------------------------------------------------------------
    // macOS requires explicit user consent for privileged operations.
    // This method runs a shell script with administrator privileges,
    // prompting for the user's password.
    //
    // The `throws` keyword indicates this can fail:
    // - User cancels the password prompt → ProcessLaunchError.userCancelled
    // - Script execution fails → ProcessLaunchError.launchFailed
    // -------------------------------------------------------------------------

    /// Executes a shell script with administrator privileges.
    ///
    /// - Parameter script: The shell script to execute
    /// - Returns: The script's standard output
    /// - Throws: ProcessLaunchError on failure or user cancellation
    ///
    /// MACOS SECURITY MODEL:
    /// macOS uses a "least privilege" security model. Apps run with limited
    /// permissions by default. To perform privileged operations (like
    /// accessing raw keyboard input), we need to:
    ///
    /// 1. Request admin privileges explicitly
    /// 2. Have the user authenticate with their password
    /// 3. Run the privileged code in a separate process
    ///
    /// We use AppleScript's `with administrator privileges` feature, which
    /// triggers macOS's standard authentication dialog.
    ///
    /// Example script: "/usr/bin/some-command --flag"
    /// This will prompt: "[App] wants to make changes. Enter your password."
    func runPrivilegedScript(_ script: String) throws -> String
}
