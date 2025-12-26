import AppKit
import Foundation

@MainActor
final class RealSystemDialogs: SystemDialogs {
    func showFatalAlert(title: String, message: String) {
        DebugLog.shared.log("Showing fatal alert: \(title) - \(message)", level: .error)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Copy Debug Log")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(DebugLog.shared.formattedLog, forType: .string)
        }

        NSApplication.shared.terminate(nil)
    }

    func runPrivilegedScript(_ script: String) throws -> String {
        DebugLog.shared.log("Running privileged script: \(script)")

        let escapedScript = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = """
        do shell script "\(escapedScript)" with administrator privileges
        """

        DebugLog.shared.log("AppleScript command: \(appleScript)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(data: outputData, encoding: .utf8) ?? ""

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        DebugLog.shared.log("osascript exit code: \(process.terminationStatus)")
        DebugLog.shared.log("osascript stdout: '\(outputString)'")
        DebugLog.shared.log("osascript stderr: '\(errorOutput)'")

        if process.terminationStatus != 0 {
            DebugLog.shared.log("osascript failed with status \(process.terminationStatus)", level: .error)
            if errorOutput.contains("-128") || process.terminationStatus == 1 {
                DebugLog.shared.log("User cancelled sudo prompt")
                throw ProcessLaunchError.userCancelled
            }
            throw ProcessLaunchError.launchFailed(errorOutput)
        }

        return outputString
    }
}
