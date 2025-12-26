import AppKit
import Foundation

enum KanataError: Error {
    case binaryNotFound
    case configNotFound
    case launchFailed(String)
    case processCrashed
}

@MainActor
final class KanataManager {
    static let kanataBinaryPath = "/opt/homebrew/bin/kanata"
    static let kanataConfigPath = "/Users/nikolai/dotfiles/kanata.kbd"
    static let logFilePath = "/tmp/kanata-ui.log"

    private let processLauncher: ProcessLauncher
    private let systemDialogs: SystemDialogs
    private let appState: AppState
    private let fileManager: FileManager

    private var monitorTimer: Timer?

    init(
        appState: AppState,
        processLauncher: ProcessLauncher,
        systemDialogs: SystemDialogs,
        fileManager: FileManager = .default
    ) {
        self.appState = appState
        self.processLauncher = processLauncher
        self.systemDialogs = systemDialogs
        self.fileManager = fileManager

        DebugLog.shared.log("KanataManager initialized")
        DebugLog.shared.log("Binary path: \(Self.kanataBinaryPath)")
        DebugLog.shared.log("Config path: \(Self.kanataConfigPath)")
    }

    func validateEnvironment() throws {
        DebugLog.shared.log("Validating environment...")

        guard fileManager.fileExists(atPath: Self.kanataBinaryPath) else {
            DebugLog.shared.log("Binary not found at \(Self.kanataBinaryPath)", level: .error)
            throw KanataError.binaryNotFound
        }
        DebugLog.shared.log("Binary exists: OK")

        guard fileManager.fileExists(atPath: Self.kanataConfigPath) else {
            DebugLog.shared.log("Config not found at \(Self.kanataConfigPath)", level: .error)
            throw KanataError.configNotFound
        }
        DebugLog.shared.log("Config exists: OK")
    }

    func startKanata() {
        DebugLog.shared.log("=== Starting Kanata ===")

        do {
            try validateEnvironment()
        } catch KanataError.binaryNotFound {
            systemDialogs.showFatalAlert(
                title: "Kanata Binary Not Found",
                message: "Kanata binary not found at \(Self.kanataBinaryPath)"
            )
            return
        } catch KanataError.configNotFound {
            systemDialogs.showFatalAlert(
                title: "Config File Not Found",
                message: "Config file not found at \(Self.kanataConfigPath)"
            )
            return
        } catch {
            systemDialogs.showFatalAlert(
                title: "Validation Error",
                message: error.localizedDescription
            )
            return
        }

        // Log output to file for debugging instead of discarding
        let script = "\(Self.kanataBinaryPath) --cfg \(Self.kanataConfigPath) > \(Self.logFilePath) 2>&1 & echo $!"

        DebugLog.shared.log("Launch script: \(script)")

        do {
            let output = try systemDialogs.runPrivilegedScript(script)
            DebugLog.shared.log("Script returned: '\(output)'")

            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.shared.log("Trimmed output: '\(trimmedOutput)'")

            guard let pid = Int(trimmedOutput) else {
                DebugLog.shared.log("Failed to parse PID from: '\(trimmedOutput)'", level: .error)
                systemDialogs.showFatalAlert(
                    title: "Launch Failed",
                    message: "Failed to parse process ID from kanata launch.\nOutput was: '\(trimmedOutput)'"
                )
                return
            }

            DebugLog.shared.log("Parsed PID: \(pid)")

            // Verify the process is actually running
            let isRunning = processLauncher.isProcessRunning(pid: pid)
            DebugLog.shared.log("Process \(pid) running check: \(isRunning)")

            if !isRunning {
                // Process already exited - read log file for error details
                DebugLog.shared.log("Process exited immediately!", level: .error)
                let logContents = readLogFile()
                DebugLog.shared.log("Log file contents:\n\(logContents)", level: .error)

                systemDialogs.showFatalAlert(
                    title: "Kanata Failed to Start",
                    message: "Process exited immediately.\n\nLog output:\n\(logContents.prefix(500))"
                )
                return
            }

            appState.kanataPID = pid
            appState.isRunning = true
            DebugLog.shared.log("Kanata started successfully with PID \(pid)")

            startMonitoring()
        } catch ProcessLaunchError.userCancelled {
            DebugLog.shared.log("User cancelled sudo prompt")
            NSApplication.shared.terminate(nil)
        } catch {
            DebugLog.shared.log("Launch failed with error: \(error)", level: .error)
            systemDialogs.showFatalAlert(
                title: "Launch Failed",
                message: "Failed to start kanata: \(error.localizedDescription)"
            )
        }
    }

    func stopKanata() {
        guard let pid = appState.kanataPID else {
            DebugLog.shared.log("stopKanata called but no PID stored")
            return
        }

        DebugLog.shared.log("Stopping Kanata (PID: \(pid))")

        stopMonitoring()
        processLauncher.terminate(pid: pid, signal: SIGTERM)
        appState.kanataPID = nil
        appState.isRunning = false

        DebugLog.shared.log("Kanata stopped")
    }

    func cleanup() {
        DebugLog.shared.log("Cleanup called, isRunning: \(appState.isRunning)")
        if appState.isRunning {
            stopKanata()
        }
    }

    private func startMonitoring() {
        DebugLog.shared.log("Starting process monitoring")
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkProcessStatus()
            }
        }
    }

    private func stopMonitoring() {
        DebugLog.shared.log("Stopping process monitoring")
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func checkProcessStatus() {
        guard let pid = appState.kanataPID else { return }

        let isRunning = processLauncher.isProcessRunning(pid: pid)

        if !isRunning {
            DebugLog.shared.log("Process \(pid) no longer running - detected crash", level: .error)

            stopMonitoring()
            appState.kanataPID = nil
            appState.isRunning = false

            let logContents = readLogFile()
            DebugLog.shared.log("Log file at crash:\n\(logContents)", level: .error)

            systemDialogs.showFatalAlert(
                title: "Kanata Crashed",
                message: "Kanata process terminated unexpectedly.\n\nLog output:\n\(logContents.prefix(500))"
            )
        }
    }

    private func readLogFile() -> String {
        do {
            let contents = try String(contentsOfFile: Self.logFilePath, encoding: .utf8)
            return contents.isEmpty ? "(empty log file)" : contents
        } catch {
            return "(could not read log file: \(error.localizedDescription))"
        }
    }
}
