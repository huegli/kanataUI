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
    }

    func validateEnvironment() throws {
        guard fileManager.fileExists(atPath: Self.kanataBinaryPath) else {
            throw KanataError.binaryNotFound
        }
        guard fileManager.fileExists(atPath: Self.kanataConfigPath) else {
            throw KanataError.configNotFound
        }
    }

    func startKanata() {
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

        let script = "\(Self.kanataBinaryPath) --cfg \(Self.kanataConfigPath) &> /dev/null & echo $!"

        do {
            let output = try systemDialogs.runPrivilegedScript(script)
            guard let pid = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                systemDialogs.showFatalAlert(
                    title: "Launch Failed",
                    message: "Failed to parse process ID from kanata launch"
                )
                return
            }

            appState.kanataPID = pid
            appState.isRunning = true
            startMonitoring()
        } catch ProcessLaunchError.userCancelled {
            NSApplication.shared.terminate(nil)
        } catch {
            systemDialogs.showFatalAlert(
                title: "Launch Failed",
                message: "Failed to start kanata: \(error.localizedDescription)"
            )
        }
    }

    func stopKanata() {
        guard let pid = appState.kanataPID else { return }

        stopMonitoring()
        processLauncher.terminate(pid: pid, signal: SIGTERM)
        appState.kanataPID = nil
        appState.isRunning = false
    }

    func cleanup() {
        if appState.isRunning {
            stopKanata()
        }
    }

    private func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkProcessStatus()
            }
        }
    }

    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func checkProcessStatus() {
        guard let pid = appState.kanataPID else { return }

        if !processLauncher.isProcessRunning(pid: pid) {
            stopMonitoring()
            appState.kanataPID = nil
            appState.isRunning = false

            systemDialogs.showFatalAlert(
                title: "Kanata Crashed",
                message: "Kanata process terminated unexpectedly"
            )
        }
    }
}
