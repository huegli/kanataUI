// RealSystemDialogs.swift
// Production implementation of SystemDialogs for real UI and privileged ops.
//
// =============================================================================
// APPKIT AND SWIFTUI
// =============================================================================
//
// macOS apps can use two UI frameworks:
// - AppKit (NSAlert, NSWindow, etc.): The original Cocoa framework (2001+)
// - SwiftUI (View, Scene, etc.): The modern declarative framework (2019+)
//
// This file uses AppKit's NSAlert because SwiftUI doesn't have a direct
// equivalent for modal, blocking alerts. In a pure SwiftUI app, you'd
// typically use .alert() modifiers, but those are non-blocking.
//
// Many macOS apps use a hybrid approach:
// - SwiftUI for the main UI (easier, more modern)
// - AppKit for features SwiftUI doesn't support (like NSAlert, NSPasteboard)
//
// =============================================================================
// OSASCRIPT AND APPLESCRIPT
// =============================================================================
//
// AppleScript is macOS's automation language. It can:
// - Control applications
// - Access system features
// - Run shell commands with elevated privileges
//
// The `with administrator privileges` clause is the official macOS way
// to request admin rights. It triggers the system password dialog.
//
// We invoke AppleScript via osascript, the command-line interpreter:
//   osascript -e 'do shell script "cmd" with administrator privileges'
//
// =============================================================================

import AppKit      // For NSAlert, NSApplication
import Foundation  // For Process, Pipe, String

// -----------------------------------------------------------------------------
// PRODUCTION IMPLEMENTATION
// -----------------------------------------------------------------------------

/// Real implementation of SystemDialogs for production use.
///
/// This class shows actual macOS UI and runs actual privileged commands.
/// The mock version (MockSystemDialogs) is used for testing.
@MainActor
final class RealSystemDialogs: SystemDialogs {

    // -------------------------------------------------------------------------
    // showFatalAlert - DISPLAY AN NSALERT
    // -------------------------------------------------------------------------
    // NSAlert is AppKit's dialog box class. It provides:
    // - A title (messageText)
    // - A body (informativeText)
    // - One or more buttons
    // - An icon (based on alertStyle)
    //
    // .runModal() blocks the thread until the user clicks a button.
    // This is appropriate for fatal errors where we can't continue.
    // -------------------------------------------------------------------------

    func showFatalAlert(title: String, message: String) {
        DebugLog.shared.log("Showing fatal alert: \(title) - \(message)", level: .error)

        // Create and configure the alert
        let alert = NSAlert()
        alert.messageText = title           // The bold title text
        alert.informativeText = message     // The smaller body text
        alert.alertStyle = .critical        // Red warning icon

        // Add buttons - they appear right-to-left
        // First button added is the "default" (rightmost) button
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Copy Debug Log")

        // Show the alert and wait for user response
        // runModal() blocks until the user clicks a button
        let response = alert.runModal()

        // Check which button was clicked
        // .alertFirstButtonReturn = first button added (Quit)
        // .alertSecondButtonReturn = second button added (Copy Debug Log)
        if response == .alertSecondButtonReturn {
            // User wants to copy the debug log before quitting
            // This is helpful for bug reports
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(DebugLog.shared.formattedLog, forType: .string)
        }

        // Terminate the application
        // This is why it's called "fatal" - the app always quits
        NSApplication.shared.terminate(nil)
    }

    // -------------------------------------------------------------------------
    // runPrivilegedScript - EXECUTE WITH ADMIN RIGHTS VIA OSASCRIPT
    // -------------------------------------------------------------------------
    // This method:
    // 1. Escapes the script for AppleScript embedding
    // 2. Wraps it in `do shell script "..." with administrator privileges`
    // 3. Runs osascript to execute it
    // 4. Handles success, failure, and user cancellation
    //
    // SECURITY CONSIDERATIONS:
    // - The script runs as root, so be careful what you execute
    // - User must explicitly approve via password
    // - We're not persisting credentials or bypassing the dialog
    // -------------------------------------------------------------------------

    func runPrivilegedScript(_ script: String) throws -> String {
        DebugLog.shared.log("Running privileged script: \(script)")

        // Escape special characters for embedding in AppleScript string
        // Backslashes and quotes need to be escaped
        let escapedScript = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Build the AppleScript command
        // `do shell script` runs a Unix command
        // `with administrator privileges` requests sudo-like access
        let appleScript = """
        do shell script "\(escapedScript)" with administrator privileges
        """

        DebugLog.shared.log("AppleScript command: \(appleScript)")

        // Configure the osascript process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

        // -e means "execute the following AppleScript expression"
        process.arguments = ["-e", appleScript]

        // Set up pipes to capture both stdout and stderr
        // Pipe() creates a pair of connected file descriptors
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Run the process and wait for completion
        try process.run()
        process.waitUntilExit()

        // Read output from both pipes
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(data: outputData, encoding: .utf8) ?? ""

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        DebugLog.shared.log("osascript exit code: \(process.terminationStatus)")
        DebugLog.shared.log("osascript stdout: '\(outputString)'")
        DebugLog.shared.log("osascript stderr: '\(errorOutput)'")

        // Handle non-zero exit codes
        // terminationStatus == 0 means success
        if process.terminationStatus != 0 {
            DebugLog.shared.log("osascript failed with status \(process.terminationStatus)", level: .error)

            // Check for user cancellation
            // When user clicks "Cancel" on the password dialog:
            // - AppleScript error -128 (userCancelledErr) is raised
            // - osascript exits with status 1
            // - stderr contains "-128" or related error text
            if errorOutput.contains("-128") || process.terminationStatus == 1 {
                DebugLog.shared.log("User cancelled sudo prompt")
                throw ProcessLaunchError.userCancelled
            }

            // Some other error occurred
            throw ProcessLaunchError.launchFailed(errorOutput)
        }

        // Success - return the command output
        return outputString
    }
}
