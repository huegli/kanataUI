import SwiftUI

@main
struct KanataUIApp: App {
    @State private var appState = AppState()
    @State private var kanataManager: KanataManager?
    @State private var showingDebugLog = false

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                appState: appState,
                kanataManager: kanataManager,
                showDebugLog: { showingDebugLog = true }
            )
        } label: {
            Image(systemName: "keyboard")
                .symbolRenderingMode(.hierarchical)
                .opacity(appState.isRunning ? 1.0 : 0.5)
        }

        Window("Debug Log", id: "debug-log") {
            DebugLogView()
        }
        .defaultSize(width: 600, height: 400)
    }

    init() {
        let state = AppState()
        _appState = State(initialValue: state)

        let manager = KanataManager(
            appState: state,
            processLauncher: RealProcessLauncher(),
            systemDialogs: RealSystemDialogs()
        )
        _kanataManager = State(initialValue: manager)

        setupTerminationHandler(manager: manager)
    }

    private func setupTerminationHandler(manager: KanataManager) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                manager.cleanup()
            }
        }
    }
}

struct MenuContent: View {
    let appState: AppState
    let kanataManager: KanataManager?
    let showDebugLog: () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Kanata: \(appState.isRunning ? "Running" : "Stopped")")
            .foregroundStyle(.secondary)

        if let pid = appState.kanataPID {
            Text("PID: \(pid)")
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        Divider()

        Button(appState.isRunning ? "Stop Kanata" : "Start Kanata") {
            if appState.isRunning {
                kanataManager?.stopKanata()
            } else {
                kanataManager?.startKanata()
            }
        }

        Divider()

        Menu("Settings") {
            Button("Open Input Monitoring Settings...") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Open Accessibility Settings...") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button("Reveal Kanata Binary in Finder") {
                NSWorkspace.shared.selectFile(KanataManager.kanataBinaryPath, inFileViewerRootedAtPath: "")
            }

            Button("Reveal Config File in Finder") {
                NSWorkspace.shared.selectFile(KanataManager.kanataConfigPath, inFileViewerRootedAtPath: "")
            }
        }

        Menu("Debug") {
            Button("Show Debug Log") {
                openWindow(id: "debug-log")
            }

            Button("Copy Debug Log") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(DebugLog.shared.formattedLog, forType: .string)
            }

            Button("Show Kanata Log in Finder") {
                NSWorkspace.shared.selectFile(KanataManager.logFilePath, inFileViewerRootedAtPath: "")
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

struct DebugLogView: View {
    @State private var logText = ""
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Debug Log")
                    .font(.headline)

                Spacer()

                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logText, forType: .string)
                }

                Button("Clear") {
                    DebugLog.shared.clear()
                    logText = ""
                }
            }
            .padding(.horizontal)
            .padding(.top)

            ScrollView {
                Text(logText.isEmpty ? "(no log entries)" : logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .onAppear {
            logText = DebugLog.shared.formattedLog
        }
        .onReceive(timer) { _ in
            logText = DebugLog.shared.formattedLog
        }
    }
}
